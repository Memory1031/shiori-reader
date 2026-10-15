import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'matcher.dart';
import 'worker.dart';

T value<T>(Result<T> result) => (result as Success<T>).value;

String fixture(int characters) {
  if (Platform.environment['SHIORI_SEARCH_SINGLE_BLOCK'] == '1') {
    return '${'山' * characters}全书末尾 MAGIC😀é';
  }
  final b = StringBuffer();
  var left = characters, chapter = 0;
  while (left > 0) {
    b.writeln('第${++chapter}章 山川');
    for (var i = 0; i < 20 && left > 0; i++) {
      final n = left.clamp(0, 512);
      b.writeln('山' * n);
      left -= n;
    }
  }
  b.write('全书末尾 MAGIC😀e\u0301');
  return b.toString();
}

Future<void> measure(int size, int repetition) async {
  final dir = await Directory.systemTemp.createTemp('shiori-search-spike-');
  final paths = AppPaths(
    support: Directory('${dir.path}/support'),
    temporary: dir,
    environment: StorageEnvironment.development,
  );
  await paths.prepare();
  final db = UserDatabase(NativeDatabase(paths.userDatabase));
  var store = value(await ManagedLocalBooks.open(paths, db));
  final token = CancellationSource().token;
  try {
    List<int> bytes = utf8.encode(fixture(size));
    final inputBytes = bytes.length;
    expect(bytes.length, lessThanOrEqualTo(LocalBookInputLimits.maxTxtBytes));
    final key = value(
      await store.importBook(
        bytes: Stream.value(bytes),
        format: LocalBookFormat.txt,
        parse: (session) => const BookDecoder().decode(
          session,
          format: LocalBookFormat.txt,
          filename: 'Synthetic.txt',
          cancellation: token,
          encoding: TxtEncoding.utf8,
          chooseEncoding: (_) async => TxtEncoding.utf8,
        ),
        cancellation: token,
      ),
    ).book.content.detail.summary.key;
    bytes = [];
    await store.close();
    store = value(await ManagedLocalBooks.open(paths, db));
    ChapterContent? readerHeld;
    if (Platform.environment['SHIORI_SEARCH_READER_HELD'] == '1') {
      readerHeld = value(
        await store.read(key, cancellation: token),
      )!.content.chapters.first;
      final other = value(
        await store.importBook(
          bytes: Stream.value(utf8.encode('用于逐出最近一次书籍快照的合成正文。')),
          format: LocalBookFormat.txt,
          parse: (session) => const BookDecoder().decode(
            session,
            format: LocalBookFormat.txt,
            filename: 'Other.txt',
            cancellation: token,
            encoding: TxtEncoding.utf8,
            chooseEncoding: (_) async => TxtEncoding.utf8,
          ),
          cancellation: token,
        ),
      ).book.content.detail.summary.key;
      value(await store.read(other, cancellation: token));
    }
    var peak = ProcessInfo.currentRss;
    final before = peak;
    final sampler = Timer.periodic(const Duration(milliseconds: 1), (_) {
      if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
    });
    addTearDown(sampler.cancel);
    final watch = Stopwatch()..start();
    final record = value(await store.read(key, cancellation: token))!;
    final cold = watch.elapsedMicroseconds;
    final coldExtra = (peak - before).clamp(0, 1 << 40);
    watch.reset();
    final warm = value(await store.read(key, cancellation: token))!;
    final warmTime = watch.elapsedMicroseconds;
    expect(identical(record, warm), isTrue);
    final heldChapter = record.content.chapters.first;
    watch.reset();
    final rows = snapshot(record.content);
    final projection = watch.elapsedMicroseconds;
    expect(identical(heldChapter, warm.content.chapters.first), isTrue);
    final manifest = await Directory('${paths.localBooks.path}/${key.novelId}')
        .list(recursive: true)
        .where((f) => f.path.endsWith('manifest.json'))
        .cast<File>()
        .first;
    final details = <String, Object?>{
      'size': size,
      'repeat': repetition,
      'inputBytes': inputBytes,
      'manifestBytes': await manifest.length(),
      'chapters': record.content.chapters.length,
      'blocks': rows.length,
      'searchableCodePoints': rows.fold<int>(
        0,
        (n, b) => n + b.text.runes.length,
      ),
      'projectionUs': projection,
      'coldUs': cold,
      'warmUs': warmTime,
      'coldReadExtraRss': coldExtra,
      'sharedWarmSnapshot': identical(record, warm),
      'readerHeldChapter': readerHeld != null,
      if (readerHeld != null)
        'readerSharesNewDecode': identical(
          readerHeld,
          record.content.chapters.first,
        ),
    };
    final searches = <Map<String, Object?>>[];
    for (final strategy in ['snapshot', 'batches']) {
      watch.reset();
      final worker = await ProbeWorker.start();
      final startup = watch.elapsedMicroseconds;
      watch.reset();
      if (strategy == 'snapshot') {
        await worker.call('load', rows);
      }
      final transfer = watch.elapsedMicroseconds;
      try {
        for (final query in ['不存在的词', '全书末尾', '山']) {
          final baseline = ProcessInfo.currentRss;
          var searchPeak = baseline;
          final searchSampler = Timer.periodic(
            const Duration(milliseconds: 1),
            (_) {
              if (ProcessInfo.currentRss > searchPeak) {
                searchPeak = ProcessInfo.currentRss;
              }
            },
          );
          watch.reset();
          var compute = 0,
              count = 0,
              retained = 0,
              firstResult = 0,
              preparation = 0;
          if (strategy == 'snapshot') {
            final reply = await worker.call('scan', (query, null, 1000));
            final (result, int us) =
                reply as (({List<ProbeHit> hits, int count}), int);
            compute = us;
            count = result.count;
            retained = result.hits.length;
            firstResult = watch.elapsedMicroseconds;
          } else {
            final parts = batches(rows, query).iterator;
            while (true) {
              final prepare = Stopwatch()..start();
              final more = parts.moveNext();
              preparation += prepare.elapsedMicroseconds;
              if (!more) break;
              final batch = parts.current;
              final reply = await worker.call('scan', (
                query,
                batch,
                1000 - retained,
              ));
              final (result, int us) =
                  reply as (({List<ProbeHit> hits, int count}), int);
              compute += us;
              count += result.count;
              retained += result.hits.length;
              if (firstResult == 0 && result.hits.isNotEmpty) {
                firstResult = watch.elapsedMicroseconds;
              }
            }
          }
          final total = watch.elapsedMicroseconds;
          searchSampler.cancel();
          if (firstResult == 0) firstResult = total;
          expect(
            count,
            query == '山'
                ? greaterThanOrEqualTo(size)
                : query == '全书末尾'
                ? 1
                : 0,
          );
          expect(retained, lessThanOrEqualTo(1000));
          searches.add({
            'strategy': strategy,
            'query': query,
            'startupUs': startup,
            'initialTransferUs': transfer,
            'computeUs': compute,
            'firstUs': firstResult,
            'totalUs': total,
            'prepareUs': preparation,
            'messagingUs': total - compute - preparation,
            'count': count,
            'retained': retained,
            'extraRss': (searchPeak - baseline).clamp(0, 1 << 40),
          });
        }
        // Acknowledgement precedes a CPU loop, so cancellation interrupts an
        // active scan rather than merely removing a queued request.
        await worker.call(
          'busy',
          strategy == 'snapshot' ? rows : batches(rows, '山').first,
        );
        watch.reset();
        value(await store.read(key, cancellation: token));
        details['${strategy}ConcurrentReadUs'] = watch.elapsedMicroseconds;
        watch.reset();
        await worker.close();
        details['${strategy}CancelUs'] = watch.elapsedMicroseconds;
        final replacement = await ProbeWorker.start();
        final done = await replacement.call('scan', ('全书末尾', rows, 1000));
        expect((done as (({List<ProbeHit> hits, int count}), int)).$1.count, 1);
        await replacement.close();
      } catch (_) {
        await worker.close();
        rethrow;
      }
    }
    // Touching a synthetic manifest invalidates the stat-keyed cache without
    // bypassing the checksum validator or reparsing the original.
    await manifest.setLastModified(
      (await manifest.lastModified()).add(const Duration(seconds: 2)),
    );
    final reread = value(await store.read(key, cancellation: token));
    expect(identical(reread, record), isFalse);
    expect(
      (await db.customSelect('SELECT * FROM reading_progress').get()),
      isEmpty,
    );
    sampler.cancel();
    details['runExtraRssPeak'] = (peak - before).clamp(0, 1 << 40);
    details['searches'] = searches;
    await store.close();
    details['rssAfterClose'] = ProcessInfo.currentRss;
    final output = Directory(
      Platform.environment['SHIORI_SEARCH_EVIDENCE'] ??
          '.tooling/local-search-spike',
    );
    await output.create(recursive: true);
    await File(
      '${output.path}/$size-$repetition.json',
    ).writeAsString(jsonEncode(details));
    // ignore: avoid_print
    print('SEARCH_PROBE ${jsonEncode(details)}');
  } finally {
    await store.close();
    await db.close();
    await dir.delete(recursive: true);
  }
}

void main() {
  final sizes =
      (Platform.environment['SHIORI_SEARCH_SIZES'] ??
              '100000,1000000,5000000,5580000')
          .split(',')
          .map(int.parse);
  final repeats = int.parse(
    Platform.environment['SHIORI_SEARCH_REPEATS'] ?? '3',
  );
  for (final size in sizes) {
    for (var repeat = 0; repeat < repeats; repeat++) {
      test(
        'validated snapshot $size repeat $repeat',
        () => measure(size, repeat),
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
}
