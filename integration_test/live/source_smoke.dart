// Android entry point, deliberately outside default offline tests.
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shiori/app/source_services.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/source_image.dart';

class _Budget {
  int attempts = 0;
  DateTime? previous;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.budget);
  final _Budget budget;
  final delegate = IOHttpClientAdapter();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (budget.attempts >= 12) throw const _Stop('budget_exhausted');
    final previous = budget.previous;
    if (previous != null) {
      final remaining =
          const Duration(seconds: 1) - DateTime.now().difference(previous);
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    }
    budget.previous = DateTime.now();
    budget.attempts++;
    return delegate.fetch(options, stream, cancel);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}

class _Stop implements Exception {
  const _Stop(this.reason);
  final String reason;
}

T _value<T>(Result<T> result) {
  if (result case Success(:final value)) return value;
  final f = (result as Failure<T>).failure;
  throw _Stop('${f.operation.name}_${f.kind.name}');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _Smoke()));
}

class _Smoke extends StatefulWidget {
  const _Smoke();
  @override
  State<_Smoke> createState() => _SmokeState();
}

class _SmokeState extends State<_Smoke> {
  String status = 'TEST001_DISABLED';
  final lines = <String>[];
  final cancellation = CancellationSource();
  @override
  void initState() {
    super.initState();
    if (const bool.fromEnvironment('TEST001_LIVE')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => run());
    }
  }

  void report(String line) {
    debugPrint(line);
    if (mounted) setState(() => lines.add(line));
  }

  Future<void> run() async {
    var stage = 'setup';
    final budget = _Budget();
    SourceServices? services;
    CacheDatabase? cache;
    try {
      // One shot even if the app process restarts. No user history or content.
      final marker = File(
        '${(await getTemporaryDirectory()).path}/test001-live-20260907.started',
      );
      if (await marker.exists()) throw const _Stop('already_started');
      await marker.writeAsString('authorized_budget_12', flush: true);
      if (mounted) setState(() => status = 'TEST001_RUNNING');
      cache = CacheDatabase(NativeDatabase.memory());
      services = SourceServices(
        cache: cache,
        adapter: _Adapter(budget),
        mediaAdapterFactory: () => _Adapter(budget),
        sourceInterval: const Duration(seconds: 1),
      );
      final token = cancellation.token;
      final id = SourceId('lightnovel');
      final book = NovelKey(sourceId: id, novelId: '31607');
      final chapterKey = ChapterKey(novelKey: book, chapterId: '309555');
      stage = 'search';
      final search = _value(
        await services.novels.search(id, '玩乐关系', cancellation: token),
      );
      final matches = search.items.where((n) => n.key == book).toList();
      if (matches.length != 1 ||
          matches.single.title != '桌游咖（玩乐关系/玩玩的戀愛關係）' ||
          !matches.single.authors.contains('葵关南')) {
        throw const _Stop('identity_mismatch');
      }
      report('TEST001_STAGE search PASS attempts=${budget.attempts}');
      stage = 'detail';
      final detail = _value(
        await services.novels.loadDetail(
          book,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
      );
      if (detail.origin != LoadOrigin.remote ||
          detail.value.summary.key != book) {
        throw const _Stop('identity_mismatch');
      }
      report('TEST001_STAGE detail PASS attempts=${budget.attempts}');
      stage = 'catalog';
      final catalog = _value(
        await services.novels.loadCatalog(
          book,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
      ).value;
      if (catalog.flatChapters
              .where((c) => c.key == chapterKey && c.volumeGroupId == '44117')
              .length !=
          1) {
        throw const _Stop('chapter_missing');
      }
      report(
        'TEST001_STAGE catalog PASS volumes=${catalog.volumes.length} chapters=${catalog.flatChapters.length} attempts=${budget.attempts}',
      );
      stage = 'chapter';
      final content = _value(
        await services.novels.loadChapter(
          chapterKey,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
      ).value;
      if (content.key != chapterKey ||
          !content.blocks.whereType<ParagraphBlock>().any(
            (b) => b.text.trim().isNotEmpty,
          )) {
        throw const _Stop('empty_or_wrong_chapter');
      }
      final images = content.blocks.whereType<ImageBlock>().toList();
      if (images.isEmpty) throw const _Stop('missing_illustration');
      report(
        'TEST001_STAGE chapter PASS blocks=${content.blocks.length} images=${images.length} attempts=${budget.attempts}',
      );
      stage = 'illustration';
      final lease = _value(
        await services.images.load(
          images.first.media,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
      ).value;
      try {
        final decoded = await decodeSourceImage(lease.data, 1024);
        report(
          'TEST001_STAGE illustration PASS width=${decoded.intrinsicSize.width.toInt()} height=${decoded.intrinsicSize.height.toInt()} attempts=${budget.attempts}',
        );
        decoded.image.dispose();
      } finally {
        await lease.close();
      }
      stage = 'local_read';
      final before = budget.attempts;
      final local = _value(
        await services.novels.loadChapter(
          chapterKey,
          mode: ReadMode.cacheOnly,
          cancellation: token,
        ),
      );
      if (local.origin != LoadOrigin.local ||
          local.value.contentRevision != content.contentRevision ||
          budget.attempts != before) {
        throw const _Stop('cache_invariant');
      }
      report('TEST001_STAGE local_read PASS attempts=${budget.attempts}');
      status = 'TEST001_PASS';
      report('$status attempts=${budget.attempts}');
    } catch (error) {
      status = 'TEST001_FAIL';
      report(
        '$status stage=$stage reason=${error is _Stop ? error.reason : 'runtime_failure'} attempts=${budget.attempts}',
      );
    } finally {
      await services?.close();
      await cache?.close();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status),
            const SizedBox(height: 16),
            for (final line in lines) Text(line),
          ],
        ),
      ),
    ),
  );
}
