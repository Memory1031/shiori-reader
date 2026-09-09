import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:shiori/data/local/record_codec.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import '../../domain/reparse_position_test.dart' as fixtures;
import 'support/epub_fixtures.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';

T ok<T>(Result<T> r) {
  expect(r, isA<Success<T>>());
  return (r as Success<T>).value;
}

CancellationToken token() => CancellationSource().token;
void main() {
  late Directory temp;
  late AppPaths paths;
  late UserDatabase db;
  late ManagedLocalBooks store;
  late LocalLibraryRepository library;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('reparse-test-');
    paths = AppPaths(
      support: Directory('${temp.path}/s'),
      temporary: temp,
      environment: StorageEnvironment.development,
    );
    await paths.prepare();
    db = UserDatabase(NativeDatabase(paths.userDatabase));
    store = ok(await ManagedLocalBooks.open(paths, db));
    library = LocalLibraryRepository(db);
  });
  tearDown(() async {
    await store.close();
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<LocalBookRecord> add([
    String source = '第一章\nSome sufficiently long text for reading.',
  ]) async => ok(
    await store.importBook(
      bytes: Stream.value(utf8.encode(source)),
      format: LocalBookFormat.txt,
      addToShelf: true,
      cancellation: token(),
      parse: (s) => const BookDecoder().decode(
        s,
        format: LocalBookFormat.txt,
        filename: 'Title.txt',
        cancellation: token(),
        encoding: TxtEncoding.utf8,
        chooseEncoding: (_) async => TxtEncoding.utf8,
      ),
    ),
  );
  test(
    'atomic reparse preserves progress, original and dates; old writer rejected even with new generation',
    () async {
      final old = await add();
      final key = old.content.detail.summary.key;
      final generation = ok(
        await library.beginProgressSession(key, cancellation: token()),
      );
      final p = fixtures.progress(old.content);
      ok(
        await library.saveProgress(
          p,
          stamp: ProgressWriteStamp(generation: generation, sequence: 0),
          cancellation: token(),
        ),
      );
      final original = File('${paths.localBooks.path}/${key.novelId}/original');
      final bytes = await original.readAsBytes();
      final result = ok(
        await store.reparseBook(
          key,
          chooseEncoding: (_) async => TxtEncoding.utf8,
          cancellation: token(),
        ),
      );
      expect(result.approximate, isFalse);
      expect(await original.readAsBytes(), bytes);
      final next = ok(await store.read(key, cancellation: token()))!;
      expect(next.importedAt, old.importedAt);
      expect(next.content.detail.summary.title, 'Title');
      final saved = ok(await library.getProgress(key, cancellation: token()))!;
      expect(saved.lastReadAt, p.lastReadAt);
      expect(saved.position.pixelOffset, isNull);
      expect(
        ok(
          await library.saveProgress(
            p,
            stamp: ProgressWriteStamp(generation: generation, sequence: 1),
            cancellation: token(),
          ),
        ),
        isFalse,
      );
      await store.close();
      store = ok(await ManagedLocalBooks.open(paths, db));
      expect(
        ok(await store.read(key, cancellation: token()))!.content.chapters,
        next.content.chapters,
      );
      expect(
        await File(
          '${paths.localBooks.path}/${key.novelId}/manifest.json',
        ).exists(),
        isFalse,
      );
    },
  );
  test('bad original leaves active manifest and progress untouched', () async {
    final old = await add();
    final key = old.content.detail.summary.key;
    await File(
      '${paths.localBooks.path}/${key.novelId}/original',
    ).writeAsString('bad');
    expect(
      await store.reparseBook(
        key,
        chooseEncoding: (_) async => TxtEncoding.utf8,
        cancellation: token(),
      ),
      isA<Failure<LocalReparseResult>>(),
    );
    expect(
      ok(await store.read(key, cancellation: token()))!.content.chapters,
      old.content.chapters,
    );
    expect(
      ok(await library.beginProgressSession(key, cancellation: token())),
      greaterThan(0),
    );
  });
  test('cancel before work preserves book', () async {
    final old = await add();
    final source = CancellationSource()..cancel();
    expect(
      await store.reparseBook(
        old.content.detail.summary.key,
        chooseEncoding: (_) async => TxtEncoding.utf8,
        cancellation: source.token,
      ),
      isA<Failure<LocalReparseResult>>(),
    );
    expect(
      ok(
        await store.read(old.content.detail.summary.key, cancellation: token()),
      ),
      isNotNull,
    );
  });
  test(
    'SQL failure after bundle creation rolls back and permits retry',
    () async {
      final old = await add();
      final key = old.content.detail.summary.key;
      await db.customStatement(
        "CREATE TRIGGER fail_reparse BEFORE UPDATE OF active_bundle ON local_books BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      expect(
        await store.reparseBook(
          key,
          chooseEncoding: (_) async => TxtEncoding.utf8,
          cancellation: token(),
        ),
        isA<Failure<LocalReparseResult>>(),
      );
      expect(
        ok(await store.read(key, cancellation: token()))!.content.chapters,
        old.content.chapters,
      );
      await db.customStatement('DROP TRIGGER fail_reparse');
      ok(
        await store.reparseBook(
          key,
          chooseEncoding: (_) async => TxtEncoding.utf8,
          cancellation: token(),
        ),
      );
    },
  );
  test(
    'EPUB repeated occurrences and nav first target survive published reparse',
    () async {
      final files = epubFiles();
      files['OPS/text/a.xhtml'] = utf8.encode(
        utf8
            .decode(files['OPS/text/a.xhtml']!)
            .replaceFirst('<body>', '<body><div style="float:right">')
            .replaceFirst('</body>', '</div></body>'),
      );
      final opf = files.keys.firstWhere((k) => k.endsWith('.opf'));
      files[opf] = utf8.encode(
        utf8
            .decode(files[opf]!)
            .replaceFirst(
              '<itemref idref="a"/>',
              '<itemref idref="a"/><itemref idref="a"/><itemref idref="a"/>',
            ),
      );
      final old = ok(
        await store.importBook(
          bytes: Stream.value(zipFiles(files)),
          format: LocalBookFormat.epub,
          cancellation: token(),
          parse: (s) => const BookDecoder().decode(
            s,
            format: LocalBookFormat.epub,
            filename: 'book.epub',
            cancellation: token(),
            chooseEncoding: (_) async => TxtEncoding.utf8,
          ),
        ),
      );
      final cs = old.content.chapters;
      expect(cs.length, 4);
      expect(cs.map((c) => c.key).toSet().length, 4);
      expect(cs[0].blocks, cs[1].blocks);
      expect(cs[0].blocks, cs[2].blocks);
      expect(old.content.navigation.last.chapterKey, cs.first.key);
      ok(
        await store.reparseBook(
          old.content.detail.summary.key,
          chooseEncoding: (_) async => TxtEncoding.utf8,
          cancellation: token(),
        ),
      );
      expect(
        ok(
          await store.read(
            old.content.detail.summary.key,
            cancellation: token(),
          ),
        )!.content.chapters,
        cs,
      );
      final html = ok(
        await store.loadPagePresentation(cs.first.key, cancellation: token()),
      );
      expect(html, contains('float:right'));
      expect(
        ok(await store.loadPagePresentation(cs[1].key, cancellation: token())),
        html,
      );
      final image = cs.first.blocks.whereType<ImageBlock>().first;
      expect(
        ok(await store.readMedia(image.media, cancellation: token())),
        tinyPng,
      );
      files[opf] = utf8.encode(
        utf8.decode(files[opf]!).replaceFirst('version="3.0"', 'version="2.0"'),
      );
      expect(
        () => EpubParser(
          zipFiles(files),
          old.content.detail.summary.key,
          'book',
        ).parse(),
        throwsA(isA<LocalParseException>()),
      );
    },
  );
  Future<void> removeEncoding(LocalBookRecord old) async {
    final key = old.content.detail.summary.key;
    final f = File('${paths.localBooks.path}/${key.novelId}/manifest.json');
    final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    map.remove('txtEncoding');
    final bytes = utf8.encode(jsonEncode(map));
    await f.writeAsBytes(bytes, flush: true);
    await db.customStatement(
      'UPDATE local_books SET manifest_hash=? WHERE digest=?',
      [sha256.convert(bytes).toString(), key.novelId],
    );
  }

  test(
    'history cleared during encoding preview is not resurrected; new session blocked',
    () async {
      final old = await add('中文正文用于编码预览');
      await removeEncoding(old);
      final key = old.content.detail.summary.key;
      final generation = ok(
        await library.beginProgressSession(key, cancellation: token()),
      );
      ok(
        await library.saveProgress(
          fixtures.progress(old.content),
          stamp: ProgressWriteStamp(generation: generation, sequence: 0),
          cancellation: token(),
        ),
      );
      final entered = Completer<void>(), choice = Completer<TxtEncoding>();
      final run = store.reparseBook(
        key,
        chooseEncoding: (_) {
          entered.complete();
          return choice.future;
        },
        cancellation: token(),
      );
      await entered.future;
      expect(
        await library.beginProgressSession(key, cancellation: token()),
        isA<Failure<int>>(),
      );
      ok(await library.clearHistory(key, cancellation: token()));
      choice.complete(TxtEncoding.utf8);
      expect(await run, isA<Failure<LocalReparseResult>>());
      expect(ok(await library.getProgress(key, cancellation: token())), isNull);
      expect(
        ok(await store.read(key, cancellation: token()))!.content.chapters,
        old.content.chapters,
      );
    },
  );
  test(
    'cancel during pending preview releases maintenance without publishing',
    () async {
      final old = await add('中文正文用于编码预览');
      await removeEncoding(old);
      final entered = Completer<void>();
      final cancellation = CancellationSource();
      final run = store.reparseBook(
        old.content.detail.summary.key,
        chooseEncoding: (_) {
          entered.complete();
          return Completer<TxtEncoding>().future;
        },
        cancellation: cancellation.token,
      );
      await entered.future;
      cancellation.cancel();
      expect(await run, isA<Failure<LocalReparseResult>>());
      expect(
        ok(
          await store.read(
            old.content.detail.summary.key,
            cancellation: token(),
          ),
        )!.content.chapters,
        old.content.chapters,
      );
      expect(
        ok(
          await library.beginProgressSession(
            old.content.detail.summary.key,
            cancellation: token(),
          ),
        ),
        greaterThan(0),
      );
    },
  );
  test(
    'startup reclaims precommit bundles and staging but retains legacy data',
    () async {
      final old = await add();
      final key = old.content.detail.summary.key;
      final orphan = Directory(
        '${paths.localBooks.path}/${key.novelId}/revisions/${'b' * 64}',
      );
      await orphan.create(recursive: true);
      await File('${orphan.path}/manifest.json').writeAsString('unfinished');
      final stage = await paths.localImportStaging.createTemp('import-');
      await db.customStatement('UPDATE local_books SET maintenance=1');
      await store.close();
      store = ok(await ManagedLocalBooks.open(paths, db));
      expect(await orphan.exists(), isFalse);
      expect(await stage.exists(), isFalse);
      expect(
        ok(await store.read(key, cancellation: token()))!.content.chapters,
        old.content.chapters,
      );
      expect(
        ok(await library.beginProgressSession(key, cancellation: token())),
        greaterThan(0),
      );
    },
  );
  test(
    'startup retains active bundle and reclaims postcommit leftovers',
    () async {
      final old = await add();
      final key = old.content.detail.summary.key;
      ok(
        await store.reparseBook(
          key,
          chooseEncoding: (_) async => TxtEncoding.utf8,
          cancellation: token(),
        ),
      );
      final obsolete = Directory(
        '${paths.localBooks.path}/${key.novelId}/revisions/${'b' * 64}',
      );
      await obsolete.create();
      await File('${obsolete.path}/manifest.json').writeAsString('old');
      await store.close();
      store = ok(await ManagedLocalBooks.open(paths, db));
      expect(await obsolete.exists(), isFalse);
      expect(ok(await store.read(key, cancellation: token())), isNotNull);
    },
  );
  test(
    'damaged active bundle does not cause recovery to erase prior files',
    () async {
      final old = await add();
      final key = old.content.detail.summary.key;
      await db.customStatement('UPDATE local_books SET active_bundle=?', [
        'b' * 64,
      ]);
      await store.close();
      store = ok(await ManagedLocalBooks.open(paths, db));
      expect(
        await File(
          '${paths.localBooks.path}/${key.novelId}/manifest.json',
        ).exists(),
        isTrue,
      );
      expect(
        await store.read(key, cancellation: token()),
        isA<Failure<LocalBookRecord?>>(),
      );
    },
  );
  test(
    'revised content cannot be overwritten by old content with fresh session',
    () async {
      final old = await add();
      final key = old.content.detail.summary.key;
      final f = File('${paths.localBooks.path}/${key.novelId}/manifest.json');
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final content = old.content;
      final c = content.chapters.first;
      final changed = ChapterContent(
        key: c.key,
        title: c.title,
        blocks: [ParagraphBlock(text: 'Prior parser text')],
      );
      map['chapters'] = [RecordCodec.chapter(changed)];
      final bytes = utf8.encode(jsonEncode(map));
      await f.writeAsBytes(bytes, flush: true);
      await db.customStatement(
        'UPDATE local_books SET manifest_hash=? WHERE digest=?',
        [sha256.convert(bytes).toString(), key.novelId],
      );
      final before = ok(await store.read(key, cancellation: token()))!;
      final stale = fixtures.progress(before.content);
      ok(
        await store.reparseBook(
          key,
          chooseEncoding: (_) async => TxtEncoding.utf8,
          cancellation: token(),
        ),
      );
      final generation = ok(
        await library.beginProgressSession(key, cancellation: token()),
      );
      expect(
        ok(
          await library.saveProgress(
            stale,
            stamp: ProgressWriteStamp(generation: generation, sequence: 0),
            cancellation: token(),
          ),
        ),
        isFalse,
      );
    },
  );
}
