// Android entry point, deliberately outside default offline tests.
import 'dart:io';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
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
  bool sealed = false;
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
    if (budget.sealed || budget.attempts >= 10) {
      throw const _Stop('budget_exhausted');
    }
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
  runApp(
    const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Smoke(),
    ),
  );
}

class _Smoke extends StatefulWidget {
  const _Smoke();
  @override
  State<_Smoke> createState() => _SmokeState();
}

class _SmokeState extends State<_Smoke> {
  String status = 'READER007_DISABLED';
  final lines = <String>[];
  Widget? reader;
  final readerKey = GlobalKey();
  final cancellation = CancellationSource();
  @override
  void initState() {
    super.initState();
    if (const bool.fromEnvironment('READER007_LIVE')) {
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
    UserDatabase? users;
    MediaLease? retainedImage;
    try {
      // One shot even if the app process restarts. No user history or content.
      final marker = File(
        '${(await getTemporaryDirectory()).path}/reader007-live-20260907-v2.started',
      );
      if (await marker.exists()) throw const _Stop('already_started');
      await marker.writeAsString('authorized_budget_10', flush: true);
      if (mounted) setState(() => status = 'READER007_RUNNING');
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
      report('READER007_STAGE search PASS attempts=${budget.attempts}');
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
      report('READER007_STAGE detail PASS attempts=${budget.attempts}');
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
        'READER007_STAGE catalog PASS volumes=${catalog.volumes.length} chapters=${catalog.flatChapters.length} attempts=${budget.attempts}',
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
        'READER007_STAGE chapter PASS blocks=${content.blocks.length} images=${images.length} attempts=${budget.attempts}',
      );
      stage = 'illustration';
      final lease = retainedImage = _value(
        await services.images.load(
          images.first.media,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
      ).value;
      try {
        final decoded = await decodeSourceImage(lease.data, 1024);
        report(
          'READER007_STAGE illustration PASS width=${decoded.intrinsicSize.width.toInt()} height=${decoded.intrinsicSize.height.toInt()} attempts=${budget.attempts}',
        );
        decoded.image.dispose();
      } finally {
        // Keep the lease pinned through Reader mounting; the memory repository releases at zero references.
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
      report('READER007_STAGE local_read PASS attempts=${budget.attempts}');
      stage = 'reader_mount';
      budget.sealed = true;
      users = UserDatabase(NativeDatabase.memory());
      final library = LocalLibraryRepository(users);
      final imageIndex = content.blocks.indexOf(images.first);
      final stamp = _value(
        await library.beginProgressSession(book, cancellation: token),
      );
      _value(
        await library.saveProgress(
          ReadingProgress(
            snapshot: detail.value.summary,
            chapterKey: chapterKey,
            chapterOrdinalSnapshot: catalog.flatChapters
                .firstWhere((c) => c.key == chapterKey)
                .ordinal,
            catalogRevision: catalog.revision,
            position: ReaderPosition(
              contentRevision: content.contentRevision,
              blockKey: content.blocks[imageIndex].blockKey,
              blockIndex: imageIndex,
              blockFraction: 0,
              chapterFraction: imageIndex / content.blocks.length,
            ),
            completed: false,
            lastReadAt: DateTime.now(),
          ),
          stamp: ProgressWriteStamp(generation: stamp, sequence: 0),
          cancellation: token,
        ),
      );
      if (mounted) {
        setState(
          () => reader = KeyedSubtree(
            key: readerKey,
            child: BookReaderScreen(
              chapter: chapterKey,
              repository: services!.novels,
              library: library,
              images: _OneImage(services.images, images.first.media),
            ),
          ),
        );
      }
      var rendered = false;
      for (var check = 0; check < 30 && !rendered; check++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        rendered = _readerRendered(readerKey, chapterKey);
      }
      if (!rendered || budget.attempts != before) {
        throw const _Stop('reader_render_failed');
      }
      report('READER007_STAGE reader_mount PASS attempts=${budget.attempts}');
      if (mounted) setState(() => reader = null);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      status = 'READER007_PASS';
      report('$status attempts=${budget.attempts}');
    } catch (error) {
      status = 'READER007_FAIL';
      report(
        '$status stage=$stage reason=${error is _Stop ? error.reason : 'runtime_failure'} attempts=${budget.attempts}',
      );
    } finally {
      await retainedImage?.close();
      await services?.close();
      await cache?.close();
      await users?.close();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      reader ??
      Scaffold(
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

/// Probe bounds rendering to the already authorized first illustration.
class _OneImage implements ImageRepository {
  _OneImage(this.inner, this.allowed);
  final ImageRepository inner;
  final MediaRef allowed;
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) => ref == allowed
      ? inner.load(ref, mode: mode, cancellation: cancellation)
      : Future.value(
          Failure(
            AppFailure(
              kind: FailureKind.unsupported,
              operation: Operation.media,
            ),
          ),
        );
}

bool _readerRendered(GlobalKey key, ChapterKey chapter) {
  var hasReader = false, hasImage = false;
  void inspect(Element element) {
    final w = element.widget;
    if (w is ReaderContentView && w.content.key == chapter) hasReader = true;
    if (w is RawImage && w.image != null) hasImage = true;
    element.visitChildren(inspect);
  }

  final context = key.currentContext;
  if (context is Element) inspect(context);
  return hasReader && hasImage;
}
