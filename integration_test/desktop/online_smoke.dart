// Opt-in native Windows probe. Pass a new, explicitly authorized output directory.
// flutter build windows --release --no-pub -t integration_test/desktop/online_smoke.dart
//   --dart-define=DESKTOP_ONLINE_LIVE=true
// shiori.exe <output-directory>; restore lib/main.dart after acceptance.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/app/source_services.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/novel_detail/catalog_view.dart';
import 'package:shiori/features/novel_detail/detail_screen.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/search/search_screen.dart';
import 'package:shiori/shared/widgets/state_views.dart';

class _Stop implements Exception {
  const _Stop(this.reason);
  final String reason;
}

void check(bool condition, String reason) {
  if (!condition) throw _Stop(reason);
}

class _Budget {
  int attempts = 0;
  bool sealed = false;
  DateTime? previous;
  Future<void> tail = Future.value();
  final requests = <Map<String, Object?>>[];
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
    final previousRequest = budget.tail;
    final done = Completer<void>();
    budget.tail = done.future;
    await previousRequest;
    void release() {
      if (!done.isCompleted) done.complete();
    }

    // A cancelled request may never subscribe to the response stream.
    // It must still release the probe's serial gate for the next request.
    cancel?.then((_) => release(), onError: (Object _) => release());
    try {
      if (budget.sealed || budget.attempts >= 12) {
        throw const _Stop('budget_closed');
      }
      final previous = budget.previous;
      if (previous != null) {
        final wait =
            const Duration(seconds: 1) - DateTime.now().difference(previous);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      check(!budget.sealed, 'budget_closed');
      budget.previous = DateTime.now();
      budget.attempts++;
      final evidence = <String, Object?>{
        'attempt': budget.attempts,
        'kind': options.method == 'POST' ? 'metadata' : 'media',
      };
      budget.requests.add(evidence);
      final response = await delegate.fetch(options, stream, cancel);
      evidence['httpStatus'] = response.statusCode;
      if ([401, 403, 429].contains(response.statusCode)) budget.sealed = true;
      final body = response.stream;
      Stream<Uint8List> tracked() async* {
        try {
          yield* body;
        } finally {
          release();
        }
      }

      response.stream = tracked();
      return response;
    } catch (_) {
      release();
      rethrow;
    }
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}

// Bound media requests to one illustration; no result-list cover fan-out.
class _FirstImage implements ImageRepository {
  _FirstImage(this.inner);
  final ImageRepository inner;
  MediaRef? allowed;
  AppFailure? failure;
  bool loaded = false;
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    allowed ??= ref;
    if (ref == allowed) {
      final result = await inner.load(
        ref,
        mode: mode,
        cancellation: cancellation,
      );
      if (result case Failure(:final failure) when !failure.isCancellation) {
        this.failure = failure;
      }
      if (result is Success<LoadResult<MediaLease>>) loaded = true;
      return result;
    }
    return Future.value(
      Failure(
        AppFailure(kind: FailureKind.unsupported, operation: Operation.media),
      ),
    );
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('DESKTOP_ONLINE_LIVE')) {
    runApp(const MaterialApp(home: Scaffold(body: Text('ONLINE_DISABLED'))));
    return;
  }
  check(Platform.isWindows && args.length == 1, 'windows_output_required');
  final output = Directory(args.single).absolute;
  await output.create(recursive: true);
  final lock = File('${output.path}/online.started');
  check(!await lock.exists(), 'already_started');
  await lock.writeAsString('authorized_max_12_no_retry', flush: true);
  final budget = _Budget();
  final cache = CacheDatabase(NativeDatabase.memory());
  final users = UserDatabase(NativeDatabase.memory());
  final services = SourceServices(
    cache: cache,
    adapter: _Adapter(budget),
    mediaAdapterFactory: () => _Adapter(budget),
    sourceInterval: const Duration(seconds: 1),
  );
  final library = LocalLibraryRepository(users);
  final images = _FirstImage(services.images);
  final root = GlobalKey();
  final navigator = GlobalKey<NavigatorState>();
  final errors = <String>[];
  FlutterError.onError = (_) => errors.add('flutter_error');
  late AppRoutes routes;
  routes = AppRoutes(
    home: (_) => SearchScreen(
      repository: services.novels,
      sourceId: SourceId('lightnovel'),
      routes: routes,
    ),
    novel: (context, key) => DetailScreen(
      novel: key,
      repository: services.novels,
      onChapter: (chapter) => routes.open(context, ReaderDestination(chapter)),
    ),
    reader: (_, chapter) => BookReaderScreen(
      chapter: chapter,
      repository: services.novels,
      library: library,
      images: images,
    ),
  );
  runApp(
    KeyedSubtree(
      key: root,
      child: ShioriApp(routes: routes, navigatorKey: navigator),
    ),
  );
  final probe = _Probe(root, output, budget, errors, images);
  try {
    await probe.run().timeout(const Duration(minutes: 2));
    budget.sealed = true;
    await probe.report('passed');
  } catch (error) {
    budget.sealed = true;
    await probe.report(
      'failed',
      error is _Stop ? error.reason : 'runtime_failure',
    );
  } finally {
    runApp(const MaterialApp(home: Scaffold(body: Text('ONLINE_FINISHED'))));
    await WidgetsBinding.instance.endOfFrame;
    await services.close();
    await cache.close();
    await users.close();
    // The runner checks the report and requests a normal native window close.
  }
}

class _Probe {
  _Probe(this.root, this.output, this.budget, this.errors, this.images);
  final GlobalKey root;
  final Directory output;
  final _Budget budget;
  final List<String> errors;
  final _FirstImage images;
  final checks = <String>[];
  String stage = 'startup';

  List<Element> elements([Element? parent]) {
    final result = <Element>[];
    void visit(Element e) {
      result.add(e);
      e.visitChildren(visit);
    }

    if (parent != null) {
      visit(parent);
    } else {
      root.currentContext?.visitChildElements(visit);
    }
    return result;
  }

  List<T> widgets<T extends Widget>() =>
      elements().map((e) => e.widget).whereType<T>().toList();

  Future<void> frame() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    check(errors.isEmpty, 'flutter_error');
    if (images.failure case final failure?) {
      throw _Stop('${failure.operation.name}_${failure.kind.name}');
    }
    for (final view in widgets<FailureView>()) {
      final failure = view.failure;
      if (!failure.isCancellation &&
          failure.context != FailureContext.cacheMiss) {
        throw _Stop('${failure.operation.name}_${failure.kind.name}');
      }
    }
  }

  Future<void> until(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 55));
    do {
      await frame();
      if (ready()) return;
    } while (DateTime.now().isBefore(deadline));
    throw const _Stop('stage_timeout');
  }

  void pass() {
    checks.add(stage);
    stdout.writeln('ONLINE_STAGE $stage PASS attempts=${budget.attempts}');
  }

  Future<void> report(String status, [String? reason]) async {
    final pending = File('${output.path}/result.json.tmp');
    await pending.writeAsString(
      jsonEncode({
        'pid': pid,
        'status': status,
        'stage': stage,
        'reason': reason,
        'checks': checks,
        'attempts': budget.attempts,
        'budget': 12,
        'requests': budget.requests,
        'imageBytesLoaded': images.loaded,
      }),
      flush: true,
    );
    await pending.rename('${output.path}/result.json');
    stdout.writeln('ONLINE_RESULT $status attempts=${budget.attempts}');
  }

  ReaderContentView get reader => widgets<ReaderContentView>().single;

  Future<void> run() async {
    await until(() => widgets<TextField>().isNotEmpty);
    stage = 'search';
    final input = widgets<TextField>().single;
    input.controller!.text = '玩乐关系';
    input.onChanged!('玩乐关系');
    await frame();
    input.onSubmitted!('玩乐关系');
    final book = NovelKey(sourceId: SourceId('lightnovel'), novelId: '31607');
    await until(() => elements().any((e) => e.widget.key == ValueKey(book)));
    pass();
    final row = elements().singleWhere((e) => e.widget.key == ValueKey(book));
    elements(row).map((e) => e.widget).whereType<InkWell>().single.onTap!();
    stage = 'detail';
    await until(
      () => widgets<TextButton>().any(
        (w) => w.key == const ValueKey('detail-catalog'),
      ),
    );
    pass();
    stage = 'catalog';
    widgets<TextButton>()
        .singleWhere((w) => w.key == const ValueKey('detail-catalog'))
        .onPressed!();
    await until(
      () =>
          widgets<CatalogScreen>().isNotEmpty &&
          widgets<CatalogView>().isNotEmpty,
    );
    final chapter = ChapterKey(novelKey: book, chapterId: '309555');
    final catalogElement = elements().singleWhere(
      (e) => e.widget is CatalogScreen,
    );
    final catalog = elements(
      catalogElement,
    ).map((e) => e.widget).whereType<CatalogView>().single;
    check(
      catalog.catalog.flatChapters.any((c) => c.key == chapter),
      'chapter_missing',
    );
    pass();
    stage = 'reader';
    catalog.onSelect(chapter);
    await until(
      () =>
          widgets<ReaderContentView>().length == 1 &&
          reader.session?.restoreStatus == ReaderRestoreStatus.ready &&
          reader.viewportController?.capture() != null &&
          !reader.viewportController!.isRestoring,
    );
    check(
      reader.content.key == chapter &&
          reader.content.blocks.whereType<ParagraphBlock>().any(
            (b) => b.text.trim().isNotEmpty,
          ),
      'chapter_invalid',
    );
    pass();
    stage = 'pagination';
    final pages = reader.viewportController!;
    final before = pages.capture()!;
    await pages.next();
    await frame();
    check(
      pages.capture()!.chapterFraction > before.chapterFraction,
      'page_not_advanced',
    );
    await pages.previous();
    await frame();
    check(
      pages.capture()!.blockKey == before.blockKey &&
          pages.capture()!.blockFraction == before.blockFraction,
      'page_return_mismatch',
    );
    pass();
    stage = 'illustration';
    final content = reader.content;
    final index = content.blocks.indexWhere((b) => b is ImageBlock);
    check(index >= 0, 'missing_illustration');
    pages.restore(
      ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks[index].blockKey,
        blockIndex: index,
        blockFraction: 0,
        chapterFraction: index / content.blocks.length,
      ),
    );
    await until(
      () =>
          !pages.isRestoring && widgets<RawImage>().any((w) => w.image != null),
    );
    pass();
    check(budget.attempts <= 12, 'budget_exceeded');
  }
}
