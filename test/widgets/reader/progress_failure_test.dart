import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/app_exit.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_chrome.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import 'link_return_test.dart' show returnBook, ReturnRepository;
import 'local_reading_test.dart' show MemoryBooks;
import 'restore_test.dart' show ObservedLibrary;

class FailureLibrary extends ObservedLibrary {
  FailureLibrary(super.inner);
  bool failWrite = false,
      failOpen = false,
      obsolete = false,
      controlWrites = false;
  final pendingWrites = <Completer<Result<bool>>>[];
  @override
  Future<Result<int>> beginProgressSession(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    if (failOpen) {
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.progressWrite,
        ),
      );
    }
    return super.beginProgressSession(key, cancellation: cancellation);
  }

  @override
  Future<Result<bool>> saveProgress(
    ReadingProgress value, {
    required ProgressWriteStamp stamp,
    required CancellationToken cancellation,
    LoadResult<Catalog>? catalog,
  }) async {
    writes.add(value);
    if (controlWrites) {
      final pending = Completer<Result<bool>>();
      pendingWrites.add(pending);
      final result = await pending.future;
      if (result is! Success<bool> || !result.value) return result;
    }
    if (obsolete) return const Success(false);
    if (failWrite) {
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.progressWrite,
        ),
      );
    }
    return inner.saveProgress(
      value,
      stamp: stamp,
      cancellation: cancellation,
      catalog: catalog,
    );
  }
}

class MetadataRepository extends ReturnRepository {
  MetadataRepository(super.store);
  bool failDetail = false;
  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => failDetail
      ? Failure(
          AppFailure(kind: FailureKind.cache, operation: Operation.novelDetail),
        )
      : super.loadDetail(key, mode: mode, cancellation: cancellation);
}

class FailedReader {
  FailedReader(
    this.book,
    this.repository,
    this.library,
    this.inner,
    this.boundary,
    this.navigator,
  );
  final LocalBookContent book;
  final MetadataRepository repository;
  final FailureLibrary library;
  final FixtureLibraryRepository inner;
  final GlobalKey boundary;
  final GlobalKey<NavigatorState> navigator;
  ReaderContentView view(WidgetTester tester) => tester
      .widgetList<ReaderContentView>(find.byType(ReaderContentView))
      .firstWhere((v) => v.appearanceActive == true);
  ChapterKey key(String title) =>
      book.chapters.firstWhere((c) => c.title == '$title opening').key;
  void link(WidgetTester tester, String label) =>
      view(tester).actions.contentLink!(
        book.links.firstWhere(
          (l) => l.source == view(tester).content.key && l.label == label,
        ),
      );
  Future<ReadingProgress?> saved() async =>
      (await inner.getProgress(
                book.detail.summary.key,
                cancellation: CancellationSource().token,
              )
              as Success<ReadingProgress?>)
          .value;
}

Future<FailedReader> mount(
  WidgetTester tester, {
  bool readFailure = false,
  bool openFailure = false,
  bool metadataFailure = false,
  bool seed = false,
  String language = 'en',
  bool dark = false,
  double scale = 1,
  Size size = const Size(400, 800),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final book = returnBook();
  final repository = MetadataRepository(
    MemoryBooks(
      LocalBookRecord(
        content: book,
        format: LocalBookFormat.epub,
        importedAt: DateTime.utc(2026),
      ),
    ),
  )..failDetail = metadataFailure;
  final inner = FixtureLibraryRepository();
  final library = FailureLibrary(inner)
    ..failRead = readFailure
    ..failOpen = openFailure;
  final boundary = GlobalKey(), navigator = GlobalKey<NavigatorState>();
  final reader = FailedReader(
    book,
    repository,
    library,
    inner,
    boundary,
    navigator,
  );
  if (seed) {
    final content = book.chapters.firstWhere((c) => c.key == reader.key('a'));
    final generation =
        (await inner.beginProgressSession(
                  content.key.novelKey,
                  cancellation: CancellationSource().token,
                )
                as Success<int>)
            .value;
    await inner.saveProgress(
      ReadingProgress(
        snapshot: book.detail.summary,
        chapterKey: content.key,
        chapterOrdinalSnapshot: 1,
        catalogRevision: book.catalog.revision,
        completed: false,
        lastReadAt: DateTime.utc(2026),
        position: ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks[8].blockKey,
          blockIndex: 8,
          blockFraction: .2,
          chapterFraction: ReaderPosition.fractionFor(
            blockIndex: 8,
            blockFraction: .2,
            blockCount: content.blocks.length,
          ),
        ),
      ),
      stamp: ProgressWriteStamp(generation: generation, sequence: 0),
      cancellation: CancellationSource().token,
    );
  }
  final settings = FixtureSettingsStore();
  await settings.save(
    ReaderSettings(
      controlsHintSeen: true,
      pageTurn: PageTurnStyle.none,
      themeMode: dark ? ReaderThemeMode.dark : ReaderThemeMode.light,
    ),
    cancellation: CancellationSource().token,
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: ShioriApp(
        locale: Locale(language),
        navigatorKey: navigator,
        overlayBuilder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            alwaysUse24HourFormat: true,
          ),
          child: child,
        ),
        routes: AppRoutes(home: (_) => const Scaffold(body: Text('Shelf'))),
      ),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => BookReaderScreen(
          chapter: reader.key('a'),
          repository: repository,
          library: library,
          settings: settings,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    library.controlWrites = false;
    for (final pending in library.pendingWrites) {
      if (!pending.isCompleted) pending.complete(const Success(true));
    }
    if (library.pending != null && !library.pending!.isCompleted) {
      library.pending!.complete(const Success(null));
    }
    library.pending = null;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await repository.invalidationsController.close();
    await inner.close();
  });
  return reader;
}

Future<void> turn(WidgetTester tester, FailedReader reader) async {
  unawaited(reader.view(tester).viewportController!.next());
  await tester.pumpAndSettle();
}

Future<void> failWrite(WidgetTester tester, FailedReader reader) async {
  reader.library.failWrite = true;
  await turn(tester, reader);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  expect(
    reader.view(tester).session!.progressStatus,
    ReaderProgressStatus.unsaved,
  );
}

Future<void> retry(
  WidgetTester tester,
  FailedReader reader, {
  bool read = false,
  String language = 'en',
}) async {
  reader.view(tester).chrome!.value = true;
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip(language == 'en' ? 'More' : '更多'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(
      language == 'en'
          ? (read ? 'Retry reading progress' : 'Retry saving progress')
          : (read ? '重试读取进度' : '重试保存进度'),
    ),
  );
  await tester.pumpAndSettle();
}

void hiddenChrome(WidgetTester tester, FailedReader reader) =>
    reader.view(tester).chrome!.value = false;

Future<void> snapshot(
  WidgetTester tester,
  FailedReader reader,
  String name,
) async {
  final path = Platform.environment['SHIORI_SAVE_SCREENSHOTS'];
  if (path == null) return;
  await tester.pump();
  await tester.runAsync(() async {
    final render =
        reader.boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  for (final seed in [false, true]) {
    testWidgets(
      'normal progress stays unchanged during coalescing and slow writes, seed=$seed',
      (tester) async {
        final reader = await mount(tester, seed: seed);
        await reader.view(tester).session!.flushProgress();
        reader.library.controlWrites = true;
        await turn(tester, reader);
        await tester.pump(const Duration(milliseconds: 299));
        expect(find.byType(ReaderProgressWarning), findsNothing);
        await tester.pump(const Duration(seconds: 1));
        for (var i = 0; i < 3; i++) {
          await turn(tester, reader);
        }
        expect(find.byType(ReaderProgressWarning), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(
          reader.view(tester).session!.progressStatus,
          ReaderProgressStatus.normal,
        );
      },
    );
  }

  testWidgets(
    'exit flushes the last stable sample while reflow is pending without a false warning',
    (tester) async {
      final reader = await mount(tester);
      await reader.view(tester).session!.flushProgress();
      await turn(tester, reader);
      final source = reader.view(tester);
      final position = source.viewportController!.capture();
      source.session!.restoringProgress();
      expect(source.session!.progressStatus, ReaderProgressStatus.normal);
      source.actions.leave!();
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect((await reader.saved())!.position, position);
    },
  );

  testWidgets(
    'write retry stays warned until the latest anchor commits; Chrome progress stays usable',
    (tester) async {
      final reader = await mount(tester);
      await reader.view(tester).session!.flushProgress();
      final viewport = reader.view(tester).viewportController!;
      final before = viewport.inspectDisplayedPage()!;
      await failWrite(tester, reader);
      expect(find.text('Not saved'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(viewport.inspectDisplayedPage()!.height, before.height);
      expect(viewport.inspectDisplayedPage()!.width, before.width);
      await retry(tester, reader);
      expect(
        reader.view(tester).session!.progressStatus,
        ReaderProgressStatus.unsaved,
      );
      expect(
        tester.widget<ReaderBottomBar>(find.byType(ReaderBottomBar)).onProgress,
        isNotNull,
      );
      reader.library.failWrite = false;
      reader.library.controlWrites = true;
      await retry(tester, reader);
      expect(reader.library.pendingWrites, hasLength(1));
      hiddenChrome(tester, reader);
      await tester.pumpAndSettle();
      expect(find.text('Not saved'), findsOneWidget);
      await turn(tester, reader);
      final latest = viewport.capture()!;
      reader.library.pendingWrites.first.complete(const Success(true));
      await tester.pumpAndSettle();
      expect(reader.library.pendingWrites, hasLength(2));
      expect(find.text('Not saved'), findsOneWidget);
      reader.library.controlWrites = false;
      reader.library.pendingWrites.last.complete(const Success(true));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderProgressWarning), findsNothing);
      expect(
        reader.view(tester).session!.progressStatus,
        ReaderProgressStatus.normal,
      );
      expect((await reader.saved())!.position, latest);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'callbacks from before a read retry cannot navigate its loading session',
    (tester) async {
      final reader = await mount(tester, readFailure: true, seed: true);
      final source = reader.view(tester);
      reader.library.failRead = false;
      reader.library.pending = Completer<Result<ReadingProgress?>>();
      unawaited(source.session!.retryProgress());
      await tester.pump();
      source.actions.contentLink!(
        reader.book.links.firstWhere((l) => l.label == 'B'),
      );
      source.actions.navigateChapter!(1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(source.session!.status, ReaderStatus.loading);
      expect(reader.library.writes, isEmpty);
      reader.library.pending!.complete(Success(await reader.saved()));
      reader.library.pending = null;
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, reader.key('a'));
      expect(reader.view(tester).actions.previousLocation, isNull);
    },
  );

  for (final kind in ['session', 'metadata']) {
    testWidgets('$kind failure remains visible until a real save after retry', (
      tester,
    ) async {
      final reader = await mount(
        tester,
        openFailure: kind == 'session',
        metadataFailure: kind == 'metadata',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Not saved'), findsOneWidget);
      reader.library.failOpen = false;
      reader.repository.failDetail = false;
      reader.library.controlWrites = true;
      await retry(tester, reader);
      expect(
        reader.view(tester).session!.progressStatus,
        ReaderProgressStatus.unsaved,
      );
      expect(reader.library.pendingWrites, hasLength(1));
      reader.library.controlWrites = false;
      reader.library.pendingWrites.single.complete(const Success(true));
      await tester.pumpAndSettle();
      hiddenChrome(tester, reader);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderProgressWarning), findsNothing);
    });
  }

  testWidgets(
    'read retry protects old history, keeps pause through retry/failure, and resumes after saving',
    (tester) async {
      final reader = await mount(tester, readFailure: true, seed: true);
      final saved = await reader.saved();
      expect(find.text('Paused'), findsOneWidget);
      await turn(tester, reader);
      await tester.pump(const Duration(seconds: 1));
      expect(reader.library.writes, isEmpty);
      expect(await reader.saved(), saved);
      await retry(tester, reader, read: true);
      hiddenChrome(tester, reader);
      await tester.pumpAndSettle();
      expect(find.text('Paused'), findsOneWidget);
      reader.library.failRead = false;
      reader.library.pending = Completer<Result<ReadingProgress?>>();
      final session = reader.view(tester).session!;
      unawaited(session.retryProgress());
      await tester.pump();
      expect(session.progressStatus, ReaderProgressStatus.paused);
      reader.library.controlWrites = true;
      reader.library.pending!.complete(Success(saved));
      reader.library.pending = null;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Paused'), findsOneWidget);
      expect(
        reader.library.pendingWrites,
        hasLength(1),
        reason:
            'status=${session.status}, restore=${session.restoreStatus}, failure=${session.restoreFailure}, tracker=${session.progress}, sample=${session.currentPosition}, writes=${reader.library.writes.length}',
      );
      reader.library.controlWrites = false;
      reader.library.pendingWrites.single.complete(const Success(true));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderProgressWarning), findsNothing);
      expect((await reader.saved())!.position, saved!.position);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final intent in [
    'sequential',
    'link',
    'catalog',
    'step',
    'exit',
    'app-exit',
  ]) {
    testWidgets(
      'read protection prevents unsafe $intent and preserves old data',
      (tester) async {
        final reader = await mount(tester, readFailure: true, seed: true);
        final source = reader.view(tester), saved = await reader.saved();
        if (intent == 'sequential') {
          source.actions.nextChapter!();
        }
        if (intent == 'link') {
          reader.link(tester, 'B');
        }
        if (intent == 'step') {
          source.actions.navigateChapter!(1);
        }
        if (intent == 'catalog') {
          source.chrome!.value = true;
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.list));
          await tester.pumpAndSettle();
          await tester.tap(find.text('b opening').last);
        }
        if (intent == 'exit') {
          source.actions.leave!();
        }
        if (intent == 'app-exit') {
          expect(await source.session!.saveForExit(), isFalse);
          final owner = AppExitScope.of(
            tester.element(find.byType(ReaderContentView)),
          )!;
          final exiting = owner.didRequestAppExit();
          await tester.pumpAndSettle();
          expect(await exiting, ui.AppExitResponse.cancel);
        }
        await tester.pumpAndSettle();
        expect(reader.view(tester).session, same(source.session));
        expect(reader.view(tester).actions.previousLocation, isNull);
        expect(reader.library.writes, isEmpty);
        expect(await reader.saved(), saved);
      },
    );
  }

  testWidgets(
    'cross-chapter return uses the read-protection gate; auxiliary reader stays independent',
    (tester) async {
      final reader = await mount(tester);
      await reader.view(tester).session!.flushProgress();
      reader.library.failRead = true;
      reader.link(tester, 'B');
      await tester.pumpAndSettle();
      final source = reader.view(tester),
          position = source.viewportController!.capture();
      expect(source.session!.progressStatus, ReaderProgressStatus.paused);
      source.actions.previousLocation!();
      await tester.pumpAndSettle();
      expect(reader.view(tester).session, same(source.session));
      expect(reader.view(tester).actions.previousLocation, isNotNull);
      reader.link(tester, 'Auxiliary');
      await tester.pumpAndSettle();
      expect(reader.view(tester).session!.library, isNull);
      expect(find.byType(ReaderProgressWarning), findsNothing);
      await tester.tap(find.byKey(const ValueKey('reader-location-return')));
      await tester.pumpAndSettle();
      expect(reader.view(tester).session, same(source.session));
      expect(reader.view(tester).viewportController!.capture(), position);
      expect(
        reader.view(tester).session!.progressStatus,
        ReaderProgressStatus.paused,
      );
    },
  );

  testWidgets(
    'obsolete session has no ineffective retry and can close with an honest warning',
    (tester) async {
      final reader = await mount(tester);
      await reader.view(tester).session!.flushProgress();
      reader.library.obsolete = true;
      await turn(tester, reader);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Not saved'), findsOneWidget);
      final session = reader.view(tester).session!;
      expect(session.canRetryProgress, isFalse);
      expect(await session.saveForExit(), isFalse);
      reader.view(tester).chrome!.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Retry saving progress'), findsNothing);
      reader.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      reader.view(tester).actions.leave!();
      await tester.pumpAndSettle();
      expect(find.byType(BookReaderScreen), findsNothing);
      expect(find.textContaining('Reading progress not saved'), findsOneWidget);
    },
  );

  for (final scenario in [
    ('android-zh', TargetPlatform.android, Size(400, 800), 1.0, false, 'zh'),
    ('ios-en-dark', TargetPlatform.iOS, Size(390, 844), 1.4, true, 'en'),
    (
      'android-narrow-en',
      TargetPlatform.android,
      Size(320, 700),
      1.5,
      false,
      'en',
    ),
    (
      'windows-narrow-zh',
      TargetPlatform.windows,
      Size(600, 700),
      1.5,
      true,
      'zh',
    ),
    (
      'windows-wide-en',
      TargetPlatform.windows,
      Size(1500, 900),
      1.0,
      false,
      'en',
    ),
  ]) {
    testWidgets(
      'real footer rendering ${scenario.$1}',
      (tester) async {
        final font = Platform.environment['SHIORI_SAVE_FONT'];
        final icons = Platform.environment['SHIORI_SAVE_ICON_FONT'];
        if (font != null) {
          await tester.runAsync(() async {
            final bytes = await File(font).readAsBytes();
            for (final family in [
              'Microsoft YaHei UI',
              'Roboto',
              '.SF Pro Text',
              '.SF Pro Display',
              'CupertinoSystemText',
              'CupertinoSystemDisplay',
            ]) {
              await (FontLoader(
                family,
              )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
            }
          });
        }
        if (icons != null) {
          await tester.runAsync(() async {
            final bytes = await File(icons).readAsBytes();
            await (FontLoader(
              'MaterialIcons',
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          });
        }
        const channel = MethodChannel('dev.fluttercommunity.plus/battery');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'getBatteryLevel' ? 82 : 'discharging',
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final reader = await mount(
          tester,
          size: scenario.$3,
          scale: scenario.$4,
          dark: scenario.$5,
          language: scenario.$6,
        );
        await reader.view(tester).session!.flushProgress();
        final geometry = tester.getRect(find.byType(PagedReaderViewport).first);
        await snapshot(tester, reader, '${scenario.$1}-normal');
        reader.link(tester, 'B');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('reader-location-return')).hitTestable(),
          findsOneWidget,
        );
        await snapshot(tester, reader, '${scenario.$1}-linked');
        reader.library.failWrite = true;
        await turn(tester, reader);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.byType(ReaderProgressWarning), findsOneWidget);
        final semantics = tester.ensureSemantics();
        final warning = tester.getSemantics(find.byType(ReaderProgressWarning));
        expect(warning.label, scenario.$6 == 'zh' ? '未保存' : 'Not saved');
        expect(
          warning.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
        expect(warning.flagsCollection.isButton, isFalse);
        semantics.dispose();
        expect(
          find.byType(ReaderStatusRow),
          scenario.$2 == TargetPlatform.windows ? findsNothing : findsOneWidget,
        );
        if (scenario.$2 != TargetPlatform.windows) {
          expect(find.text('82%'), findsOneWidget);
        }
        expect(
          tester.getRect(find.byType(PagedReaderViewport).first),
          geometry,
        );
        await snapshot(tester, reader, '${scenario.$1}-unsaved');
        await retry(tester, reader, language: scenario.$6);
        await snapshot(tester, reader, '${scenario.$1}-chrome');
        reader.library.failWrite = false;
        await reader.view(tester).session!.retryProgress();
        await tester.pumpAndSettle();
        hiddenChrome(tester, reader);
        await tester.pumpAndSettle();
        await snapshot(tester, reader, '${scenario.$1}-recovered');
        reader.library.failRead = true;
        // Return into a new session whose initial history read fails.
        reader.view(tester).actions.previousLocation!();
        await tester.pumpAndSettle();
        expect(find.byType(ReaderProgressWarning), findsOneWidget);
        await snapshot(tester, reader, '${scenario.$1}-paused');
        if (scenario.$1 == 'android-zh' || scenario.$1 == 'windows-narrow-zh') {
          reader.link(tester, 'Auxiliary');
          await tester.pumpAndSettle();
          expect(find.byType(ReaderProgressWarning), findsNothing);
          await snapshot(tester, reader, '${scenario.$1}-auxiliary');
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(scenario.$2),
    );
  }
}
