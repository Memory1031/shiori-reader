import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/local_chapter_progress.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_logical_progress.dart';
import 'package:shiori/features/reader/reader_preferences.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import 'cross_chapter_drag_test.dart'
    show Chapters, Harness, active, drag, layoutFrames;
import 'settings_test.dart' show Store;

final previewPlatforms = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.windows,
});

class SampledReader extends ReaderController {
  SampledReader({
    required super.repository,
    required super.chapter,
    super.library,
  });
  final samples = <(ReaderPosition, bool)>[];
  @override
  void sampleProgress(ReaderPosition position, bool completed) {
    samples.add((position, completed));
    super.sampleProgress(position, completed);
  }
}

class ProgressReader {
  ProgressReader(
    this.session,
    this.viewport,
    this.boundary,
    this.chrome,
    this.repo,
    this.env,
    this.preferences,
    this.logical,
  );
  final SampledReader session;
  final PagedReaderController viewport;
  final GlobalKey boundary;
  final ValueNotifier<bool> chrome;
  final Chapters repo;
  final FixtureEnvironment env;
  final ReaderPreferences preferences;
  final ValueNotifier<ReaderLogicalProgress?> logical;
  Future<ReadingProgress?> saved() async =>
      (await env.library.getProgress(
                session.chapter.novelKey,
                cancellation: CancellationSource().token,
              )
              as Success<ReadingProgress?>)
          .value;
  bool _closed = false;
  Future<void> close(WidgetTester tester) async {
    if (_closed) return;
    _closed = true;
    session.onDelete();
    await tester.pumpWidget(const SizedBox());
    var done = false;
    final closing = () async {
      await session.closeReader();
      session.dispose();
      chrome.dispose();
      preferences.dispose();
      logical.dispose();
      await repo.events.close();
      await env.close();
    }().whenComplete(() => done = true);
    for (var i = 0; !done && i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await closing;
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (Platform.environment['SHIORI_PROGRESS_EVIDENCE'] == null) return;
    await tester.pump();
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await screenshotProgress(tester, name, render);
  }
}

Future<void> screenshotProgress(
  WidgetTester tester,
  String name, [
  RenderRepaintBoundary? render,
]) async {
  final directory = Platform.environment['SHIORI_PROGRESS_EVIDENCE'];
  if (directory == null) return;
  if (render == null) {
    await tester.pump();
    render = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
  }
  await tester.runAsync(() async {
    final image = await render!.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<ProgressReader> mountProgress(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  ReaderSettings? settings,
  int sections = 0,
  bool loading = false,
  bool reduced = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final env = FixtureEnvironment(scenario: FixtureScenario.longChapter);
  final key = fixtureChapterKey(FixtureScenario.longChapter);
  final repo = Chapters(env.novels);
  repo.contents[key] = ChapterContent(
    key: key,
    title: 'Progress preview',
    blocks: [
      for (var i = 0; i < 30; i++)
        ParagraphBlock(text: '第 ${i + 1} 段，合成的翻页进度验证文字。' * 8),
    ],
  );
  final session = SampledReader(
    repository: repo,
    chapter: key,
    library: env.library,
  );
  await session.load();
  await session.retryProgress();
  final content = session.content!;
  final index = sections == 0
      ? null
      : LocalChapterProgressIndex.build(
          metrics: BookProgressMetrics(
            revision: 'preview',
            order: [key],
            weights: [content.blocks.length],
          ),
          chapters: [content],
          navigation: [
            for (var i = 0; i < sections; i++)
              LocalNavigationEntry(
                title: 'Same title',
                chapterKey: key,
                blockKey: content.blocks[i].blockKey,
              ),
          ],
        );
  final viewport = PagedReaderController(), boundary = GlobalKey();
  final chrome = ValueNotifier(false);
  final logical = ValueNotifier<ReaderLogicalProgress?>(
    sections == 0 && !loading
        ? null
        : ReaderLogicalProgress(
            index: index,
            loading: loading,
            navigate: (_, _) async {},
          ),
  );
  final preferences = ReaderPreferences(
    Store()..value = settings ?? ReaderSettings(controlsHintSeen: true),
  );
  await preferences.load();
  await tester.pumpWidget(
    ShioriApp(
      locale: const Locale('en'),
      overlayBuilder: reduced
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child,
            )
          : null,
      routes: AppRoutes(
        home: (_) => RepaintBoundary(
          key: boundary,
          child: ValueListenableBuilder<ReaderLogicalProgress?>(
            valueListenable: logical,
            builder: (_, value, _) => ReaderContentView(
              content: session.content!,
              session: session,
              viewportController: viewport,
              chrome: chrome,
              preferences: preferences,
              logicalProgress: value,
            ),
          ),
        ),
      ),
    ),
  );
  final reader = ProgressReader(
    session,
    viewport,
    boundary,
    chrome,
    repo,
    env,
    preferences,
    logical,
  );
  addTearDown(() => reader.close(tester));
  await tester.pumpAndSettle();
  return reader;
}

String progressLabel(WidgetTester tester) {
  final values = tester
      .widgetList<Text>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(r'^(Chapter|Document) \d+%$').hasMatch(widget.data ?? ''),
        ),
      )
      .map((text) => text.data!)
      .toSet();
  expect(values, hasLength(1), reason: 'Footer and toolbar must agree');
  return values.single;
}

int percent(WidgetTester tester) =>
    int.parse(RegExp(r'\d+').firstMatch(progressLabel(tester))![0]!);

Future<TestGesture> dragProgress(WidgetTester tester, double distance) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(PagedReaderViewport)),
  );
  await gesture.moveBy(Offset(distance.sign * 22, 0));
  await tester.pump();
  await gesture.moveBy(Offset(distance, 0));
  await tester.pump();
  return gesture;
}

void main() {
  setUpAll(() async {
    final font = Platform.environment['SHIORI_PROGRESS_FONT'];
    if (font == null) return;
    final bytes = await File(font).readAsBytes();
    for (final family in ['Roboto', 'Microsoft YaHei UI']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  testWidgets('native progress initial render', (tester) async {
    final reader = await mountProgress(tester);
    expect(reader.viewport.capture(), isNotNull);
    expect(reader.session.samples, isNotEmpty);
    await reader.screenshot(tester, 'before-phone');
    await reader.close(tester);
  });

  testWidgets(
    'edges and a 100 percent preview retain real completion semantics',
    (tester) async {
      final reader = await mountProgress(tester);
      final old = progressLabel(tester), initial = reader.viewport.capture();
      await reader.viewport.previous();
      await tester.pump();
      expect(progressLabel(tester), old);
      expect(reader.viewport.capture(), initial);
      final content = reader.session.content!;
      reader.viewport.restore(
        ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks.last.blockKey,
          blockIndex: content.blocks.length - 1,
          blockFraction: 1,
          chapterFraction: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(percent(tester), 100);
      await reader.viewport.next();
      await tester.pump();
      expect(percent(tester), 100);
      final previous = reader.viewport.previous();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await previous;
      final anchor = reader.viewport.capture(),
          samples = reader.session.samples.length;
      expect(reader.session.samples.last.$2, isFalse);
      final next = reader.viewport.next();
      await tester.pump();
      expect(percent(tester), 100);
      expect(reader.viewport.capture(), anchor);
      expect(reader.session.samples, hasLength(samples));
      expect(reader.session.samples.last.$2, isFalse);
      expect(
        reader.session.progress!.bookProgress!.terminal,
        BookTerminalState.reading,
      );
      await reader.screenshot(tester, 'last-page-preview');
      await tester.pump(const Duration(milliseconds: 300));
      await next;
      expect(percent(tester), 100);
      expect(reader.session.samples.last.$2, isTrue);
      expect(
        reader.session.progress!.bookProgress!.terminal,
        BookTerminalState.reading,
      );
      await reader.close(tester);
    },
  );

  for (final landed in [false, true]) {
    testWidgets(
      'normal exit ${landed ? 'after' : 'during'} turn saves only a stable anchor',
      (tester) async {
        final reader = await mountProgress(tester);
        await reader.session.flushProgress();
        final original = await reader.saved();
        final turn = reader.viewport.next();
        await tester.pump();
        if (landed) {
          await tester.pump(const Duration(milliseconds: 300));
          await turn;
        }
        final stable = reader.viewport.capture();
        final exit = tester.binding.handleRequestAppExit();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(await exit, ui.AppExitResponse.exit);
        final saved = await reader.saved();
        expect(saved!.position, stable);
        if (!landed) expect(saved, original);
        expect(saved.bookProgress!.terminal, BookTerminalState.reading);
        await turn;
        await reader.close(tester);
      },
    );
  }

  testWidgets(
    'metadata replacement invalidates cached endpoints for the whole turn',
    (tester) async {
      final reader = await mountProgress(tester, sections: 1);
      final old = progressLabel(tester),
          oldIndex = reader.logical.value!.index!;
      final turn = reader.viewport.next();
      await tester.pump();
      expect(progressLabel(tester), isNot(old));
      final content = reader.session.content!;
      final replacement = LocalChapterProgressIndex.build(
        metrics: oldIndex.metrics,
        chapters: [content],
        navigation: oldIndex.navigation,
      );
      reader.logical.value = ReaderLogicalProgress(
        index: replacement,
        navigate: (_, _) async {},
      );
      await tester.pump();
      await tester.pump();
      expect(progressLabel(tester), old);
      await tester.pump(const Duration(milliseconds: 120));
      expect(progressLabel(tester), old);
      await tester.pump(const Duration(milliseconds: 180));
      await turn;
      expect(progressLabel(tester), isNot(old));
      await reader.close(tester);
    },
  );

  testWidgets('late end of an old preview cannot clear a newer operation', (
    tester,
  ) async {
    final reader = await mountProgress(tester);
    final callback = tester
        .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
        .onTurnPreview!;
    final from = reader.viewport.capture()!, content = reader.session.content!;
    ReaderTurnPreview preview(int block) => ReaderTurnPreview(
      from: (position: from, last: false),
      to: (
        position: ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks[block].blockKey,
          blockIndex: block,
          blockFraction: 0,
          chapterFraction: block / content.blocks.length,
        ),
        last: false,
      ),
      layoutGeneration: reader.viewport.layoutGeneration,
      discrete: true,
    );
    final old = preview(3), current = preview(6);
    callback(old, 0);
    callback(current, 0);
    await tester.pump();
    final shown = progressLabel(tester);
    callback(old, null);
    await tester.pump();
    expect(progressLabel(tester), shown);
    expect(reader.viewport.capture(), from);
    callback(current, null);
    await tester.pump();
    expect(percent(tester), 0);
    final end = ReaderTurnPreview(
      from: (position: from, last: true),
      to: (
        position: ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks[6].blockKey,
          blockIndex: 6,
          blockFraction: .9,
          chapterFraction: .23,
        ),
        last: false,
      ),
      layoutGeneration: reader.viewport.layoutGeneration,
      discrete: false,
    );
    callback(end, 1);
    await tester.pump();
    expect(
      percent(tester),
      23,
      reason: 'Interpolation must finish at the exact formatted endpoint',
    );
    expect(reader.viewport.capture(), from);
    callback(end, null);
    await reader.close(tester);
  });

  for (final commit in [false, true]) {
    testWidgets(
      'cross chapter ${commit ? 'commit' : 'cancel'} keeps each page percentage in its own scope',
      (tester) async {
        final h = Harness();
        h.repository.contents[h.key(1)] = ChapterContent(
          key: h.key(1),
          title: 'Next chapter',
          blocks: [
            for (var i = 0; i < 30; i++)
              ParagraphBlock(text: 'Next chapter passage $i. ' * 20),
          ],
        );
        await h.open(tester);
        final old = active(tester).session!, sessions = h.library.sessions;
        String labelFor(ReaderController session) => tester
            .widgetList<Text>(
              find.descendant(
                of: find.byWidgetPredicate(
                  (w) =>
                      w is ReaderContentView && identical(w.session, session),
                  skipOffstage: false,
                ),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Text &&
                      RegExp(r'^Chapter \d+%$').hasMatch(w.data ?? ''),
                  skipOffstage: false,
                ),
                skipOffstage: false,
              ),
            )
            .map((w) => w.data!)
            .toSet()
            .single;
        expect(labelFor(old), 'Chapter 100%');
        final candidates = tester.widgetList<ReaderContentView>(
          find.byType(ReaderContentView, skipOffstage: false),
        );
        final candidate = candidates
            .singleWhere((v) => !identical(v.session, old))
            .session!;
        expect(candidate.progress, isNull);
        await screenshotProgress(
          tester,
          'cross-${commit ? "commit" : "cancel"}-drag',
        );
        expect(labelFor(candidate), 'Chapter 0%');
        expect(h.library.sessions, sessions);
        final gesture = await drag(tester, 1);
        await layoutFrames(tester);
        expect(labelFor(old), 'Chapter 100%');
        expect(labelFor(candidate), 'Chapter 0%');
        expect(candidate.progress, isNull);
        if (commit) {
          await gesture.up();
        } else {
          await gesture.cancel();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(h.library.sessions, sessions);
        await screenshotProgress(
          tester,
          'cross-${commit ? "commit" : "cancel"}-settle',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(active(tester).session, commit ? same(candidate) : same(old));
        expect(h.library.sessions, sessions + (commit ? 1 : 0));
        await screenshotProgress(
          tester,
          'cross-${commit ? "commit" : "cancel"}-finished',
        );
        await h.close(tester);
      },
    );
  }

  for (final keyboard in [false, true]) {
    testWidgets(
      'accepted ${keyboard ? 'key' : 'tap'} previews target before capture and save',
      (tester) async {
        final reader = await mountProgress(tester);
        final initial = reader.viewport.capture();
        final before = progressLabel(tester),
            samples = reader.session.samples.length;
        await reader.session.flushProgress();
        final saved = await reader.saved();
        if (keyboard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        } else {
          await tester.tapAt(
            tester.getCenter(find.byType(PagedReaderViewport)) +
                const Offset(130, 0),
          );
        }
        await tester.pump();
        final target = progressLabel(tester);
        expect(target, isNot(before));
        expect(reader.viewport.capture(), initial);
        expect(reader.session.samples, hasLength(samples));
        await reader.session.flushProgress();
        expect(await reader.saved(), saved);
        for (final text in tester.widgetList<Text>(
          find.byWidgetPredicate((w) => w is Text && w.data == target),
        )) {
          expect(text.semanticsLabel, before);
        }
        await reader.screenshot(tester, '${keyboard ? 'key' : 'tap'}-start');
        await tester.pump(const Duration(milliseconds: 120));
        expect(progressLabel(tester), target);
        expect(reader.viewport.capture(), initial);
        await reader.screenshot(tester, '${keyboard ? 'key' : 'tap'}-middle');
        await tester.pump(const Duration(milliseconds: 180));
        expect(reader.viewport.capture(), isNot(initial));
        expect(progressLabel(tester), target);
        expect(reader.session.samples.length, samples + 1);
        await reader.screenshot(
          tester,
          '${keyboard ? 'key' : 'tap'}-committed',
        );
        await reader.session.flushProgress();
        expect((await reader.saved())!.position, reader.viewport.capture());
        final previous = reader.viewport.previous();
        await tester.pump();
        expect(progressLabel(tester), before);
        await tester.pump(const Duration(milliseconds: 300));
        await previous;
        expect(reader.viewport.capture(), initial);
        expect(progressLabel(tester), before);
        await reader.close(tester);
      },
      variant: previewPlatforms,
    );
  }

  testWidgets(
    'queued input waits for its own turn and reverse input drops it',
    (tester) async {
      final reader = await mountProgress(tester);
      final initial = reader.viewport.capture();
      final first = reader.viewport.next(queueIfTurning: true);
      await tester.pump();
      final firstLabel = progressLabel(tester);
      await reader.viewport.next(queueIfTurning: true);
      expect(progressLabel(tester), firstLabel);
      await reader.viewport.previous(queueIfTurning: true);
      await tester.pump(const Duration(milliseconds: 300));
      await first;
      expect(progressLabel(tester), firstLabel);
      final firstAnchor = reader.viewport.capture();
      final second = reader.viewport.next(queueIfTurning: true);
      await tester.pump();
      final secondLabel = progressLabel(tester);
      await reader.viewport.next(queueIfTurning: true);
      expect(progressLabel(tester), secondLabel);
      await tester.pump(const Duration(milliseconds: 300));
      await second;
      final secondAnchor = reader.viewport.capture();
      expect(secondAnchor, isNot(firstAnchor));
      await tester.pump();
      expect(progressLabel(tester), isNot(secondLabel));
      expect(reader.viewport.capture(), secondAnchor);
      await tester.pump(const Duration(milliseconds: 300));
      expect(reader.viewport.capture(), isNot(secondAnchor));
      expect(reader.viewport.capture(), isNot(initial));
      await reader.close(tester);
    },
  );

  for (final commit in [false, true]) {
    testWidgets(
      'drag ${commit ? 'commit' : 'rebound'} updates only display until landing',
      (tester) async {
        final reader = await mountProgress(tester);
        final initial = reader.viewport.capture(), old = progressLabel(tester);
        final samples = reader.session.samples.length;
        await reader.session.flushProgress();
        final saved = await reader.saved();
        final gesture = await dragProgress(tester, commit ? -230 : -90);
        final during = percent(tester);
        expect(during, greaterThan(0));
        expect(reader.viewport.capture(), initial);
        expect(reader.session.samples, hasLength(samples));
        await reader.session.flushProgress();
        expect(await reader.saved(), saved);
        await reader.screenshot(
          tester,
          commit ? 'drag-success' : 'drag-cancel',
        );
        if (commit) {
          await gesture.up();
        } else {
          await gesture.cancel();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(
          percent(tester),
          commit ? greaterThanOrEqualTo(during) : lessThanOrEqualTo(during),
        );
        await reader.screenshot(
          tester,
          commit ? 'drag-settle' : 'drag-rebound',
        );
        await tester.pump(const Duration(milliseconds: 300));
        if (commit) {
          expect(reader.viewport.capture(), isNot(initial));
          expect(reader.session.samples.length, samples + 1);
        } else {
          expect(reader.viewport.capture(), initial);
          expect(reader.session.samples, hasLength(samples));
          expect(progressLabel(tester), old);
          expect(await reader.saved(), saved);
        }
        final finished = progressLabel(tester);
        await tester.pump(const Duration(milliseconds: 260));
        expect(progressLabel(tester), finished);
        await reader.screenshot(
          tester,
          commit ? 'drag-landed' : 'drag-cancelled',
        );
        await reader.close(tester);
      },
      variant: previewPlatforms,
    );
  }

  testWidgets('formatted previews rebuild neither body nor complete toolbar', (
    tester,
  ) async {
    final reader = await mountProgress(tester);
    reader.chrome.value = true;
    await tester.pumpAndSettle();
    final body = tester.widget<PagedReaderViewport>(
      find.byType(PagedReaderViewport),
    );
    final toolbar = tester.widget<ReaderToolbars>(find.byType(ReaderToolbars));
    final turn = reader.viewport.next();
    await tester.pump();
    final measured = reader.viewport.measuredChunks;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.widget<PagedReaderViewport>(find.byType(PagedReaderViewport)),
        same(body),
      );
      expect(
        tester.widget<ReaderToolbars>(find.byType(ReaderToolbars)),
        same(toolbar),
      );
      expect(reader.viewport.measuredChunks, measured);
      progressLabel(tester);
    }
    await reader.screenshot(tester, 'toolbar-preview');
    await tester.pump(const Duration(milliseconds: 140));
    await turn;
    await reader.close(tester);
  });

  for (final action in ['restore', 'resize', 'font', 'inactive']) {
    testWidgets('$action invalidates preview without a stale target', (
      tester,
    ) async {
      final reader = await mountProgress(tester);
      final initial = reader.viewport.capture(), old = progressLabel(tester);
      final turn = reader.viewport.next();
      await tester.pump();
      expect(progressLabel(tester), isNot(old));
      switch (action) {
        case 'restore':
          reader.viewport.restore(initial!);
        case 'resize':
          tester.view.physicalSize = const Size(430, 844);
        case 'font':
          reader.preferences.update(
            reader.preferences.value.copyWith(fontSize: 26),
          );
        case 'inactive':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
      }
      await tester.pump();
      if (action == 'resize' || action == 'font') await tester.pump();
      if (action != 'font') expect(progressLabel(tester), old);
      await tester.pump(const Duration(milliseconds: 320));
      await turn;
      if (action == 'restore') expect(reader.viewport.capture(), initial);
      if (action == 'inactive') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await reader.close(tester);
    });
  }

  for (final mode in ['none', 'reduced', 'spread', 'night']) {
    testWidgets(
      '$mode confirms display immediately with existing page semantics',
      (tester) async {
        final reader = await mountProgress(
          tester,
          size: mode == 'spread' ? const Size(1280, 900) : const Size(390, 844),
          reduced: mode == 'reduced',
          settings: ReaderSettings(
            controlsHintSeen: true,
            pageTurn: mode == 'none' ? PageTurnStyle.none : PageTurnStyle.curl,
            paper: ReaderPaper.warm,
            themeMode: mode == 'night'
                ? ReaderThemeMode.dark
                : ReaderThemeMode.light,
          ),
        );
        if (mode == 'spread') {
          expect(reader.viewport.inspectDisplayedPage()!.columns, 2);
        }
        final old = progressLabel(tester);
        final turn = reader.viewport.next();
        await tester.pump();
        final target = progressLabel(tester);
        expect(target, isNot(old));
        if (mode == 'none' || mode == 'reduced') {
          expect(reader.session.samples.last.$1, reader.viewport.capture());
        } else {
          await reader.screenshot(tester, '$mode-start');
          await tester.pump(const Duration(milliseconds: 300));
        }
        await turn;
        expect(progressLabel(tester), target);
        await reader.screenshot(tester, '$mode-landed');
        await reader.close(tester);
      },
    );
  }

  testWidgets(
    'different logical sections with equal titles never interpolate',
    (tester) async {
      final reader = await mountProgress(tester, sections: 30);
      final old = progressLabel(tester), initial = reader.viewport.capture();
      final gesture = await dragProgress(tester, -180);
      expect(progressLabel(tester), old);
      expect(reader.viewport.capture(), initial);
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 300));
      final turn = reader.viewport.next();
      await tester.pump();
      final target = progressLabel(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await turn;
      expect(progressLabel(tester), target);
      await reader.close(tester);
    },
  );

  testWidgets(
    'loading logical metadata never substitutes a physical denominator',
    (tester) async {
      final reader = await mountProgress(tester, loading: true);
      final labels = tester
          .widgetList<Text>(
            find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  (w.data ?? '').contains('Chapter progress loading'),
            ),
          )
          .map((w) => w.data)
          .toList();
      expect(labels, isNotEmpty);
      final turn = reader.viewport.next();
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'^Chapter \d+%$').hasMatch(w.data ?? ''),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await turn;
      await reader.close(tester);
    },
  );
}
