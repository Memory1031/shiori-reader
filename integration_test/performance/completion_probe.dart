// Offline production-reader probes, dispatched by the shared profile entry.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming, FramePhase;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_completion_page.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_preferences.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/viewport/page_turn.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

Iterable<Element> elements() sync* {
  final result = <Element>[];
  void visit(Element element) {
    result.add(element);
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  yield* result;
}

Future<Map<String, Object?>> runReaderProfileProbe({
  bool pagination = false,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final scenario = pagination
      ? FixtureScenario.longChapter
      : FixtureScenario.shortChapter;
  final fixture = FixtureEnvironment(scenario: scenario);
  ReaderPreferences? standalonePreferences;
  final errors = <String>[];
  final originalError = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    originalError?.call(details);
  };
  final watch = Stopwatch()..start();
  final timings = <FrameTiming>[];
  var measuring = false;
  void collect(List<FrameTiming> frames) {
    if (measuring) timings.addAll(frames);
  }

  WidgetsBinding.instance.addTimingsCallback(collect);
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<void> waitFor(bool Function() condition) async {
    final deadline = watch.elapsed + const Duration(seconds: 15);
    while (!condition()) {
      if (watch.elapsed > deadline) {
        throw StateError(
          '${pagination ? 'Pagination' : 'Completion'} probe timeout',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  ReaderContentView? reader() => elements()
      .map((e) => e.widget)
      .whereType<ReaderContentView>()
      .where((v) => v.appearanceActive == true)
      .firstOrNull;
  Future<void> idle() => waitFor(() {
    final current = reader();
    final controller = current?.viewportController;
    return controller != null &&
        !controller.isRestoring &&
        !controller.isTurning &&
        !current!.crossChapterTurning &&
        controller.inspectDisplayedPage() != null;
  });

  PageTurnFrame frame() {
    final layer = elements().firstWhere(
      (e) => e.widget.key == const ValueKey('completion-reader-layer'),
    );
    PageTurnFrame? value;
    void visit(Element e) {
      if (e.widget case PageTurnSlot slot) {
        value ??= slot.frame;
      }
      e.visitChildren(visit);
    }

    visit(layer);
    return value!;
  }

  var pointer = 0;
  Future<void> tap(Offset position) async {
    final id = ++pointer;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: id,
        position: position,
        timeStamp: watch.elapsed,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: id, position: position, timeStamp: watch.elapsed),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  Future<void> drag(bool entering, {required bool commit}) async {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    final sign = entering ? -1.0 : 1.0;
    var position = Offset(
      size.width * (entering ? .75 : .25),
      size.height * .55,
    );
    final id = ++pointer;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: id,
        position: position,
        timeStamp: watch.elapsed,
      ),
    );
    for (var i = 0; i < 18; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final delta = Offset(sign * size.width * .025, 0);
      position += delta;
      GestureBinding.instance.handlePointerEvent(
        PointerMoveEvent(
          pointer: id,
          position: position,
          delta: delta,
          timeStamp: watch.elapsed,
        ),
      );
    }
    check(
      frame().progress > .2 && frame().progress < 1,
      'Missing held intermediate frame',
    );
    check(
      (reader()!.completion != null) != entering,
      'Committed before release',
    );
    if (commit) {
      GestureBinding.instance.handlePointerEvent(
        PointerUpEvent(
          pointer: id,
          position: position,
          timeStamp: watch.elapsed,
        ),
      );
    } else {
      GestureBinding.instance.handlePointerEvent(
        PointerCancelEvent(
          pointer: id,
          position: position,
          timeStamp: watch.elapsed,
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 380));
    check(
      (reader()!.completion != null) == (commit ? entering : !entering),
      'Wrong settled completion state',
    );
  }

  try {
    await fixture.settings.save(
      ReaderSettings(controlsHintSeen: true),
      cancellation: CancellationSource().token,
    );
    runApp(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: pagination
                ? fixtureChapterKey(scenario)
                : fixture.source.data.catalog(scenario).flatChapters.last.key,
            startAtBeginning: pagination,
            repository: fixture.novels,
            library: fixture.library,
            settings: fixture.settings,
          ),
        ),
      ),
    );
    await waitFor(
      () =>
          reader()?.session?.progress != null &&
          reader()?.viewportController?.isRestoring == false,
    );
    var current = reader()!;
    current.preferences!.update(
      current.preferences!.value.copyWith(controlsHintSeen: true),
    );
    current.chrome!.value = false;
    if (pagination) {
      final results = <String, Object?>{};
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final refreshRate = view.display.refreshRate;
      final budgetUs = refreshRate > 0 ? 1000000 / refreshRate : null;
      Future<void> measure(String name, Future<void> Function() action) async {
        // Drain the engine's previous timing batch before opening a window.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        timings.clear();
        measuring = true;
        final elapsed = Stopwatch()..start();
        await action();
        elapsed.stop();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        measuring = false;
        check(timings.isNotEmpty, 'No native frame timings for $name');
        double percentile(List<int> values, double fraction) {
          values.sort();
          return values[((values.length - 1) * fraction).round()] / 1000;
        }

        final ui = timings.map((f) => f.buildDuration.inMicroseconds).toList();
        final raster = timings
            .map((f) => f.rasterDuration.inMicroseconds)
            .toList();
        results[name] = {
          'elapsedMs': elapsed.elapsedMilliseconds,
          'frames': timings.length,
          'uiP95Ms': percentile(ui, .95),
          'rasterP95Ms': percentile(raster, .95),
          'uiMaxMs': percentile(ui, 1),
          'rasterMaxMs': percentile(raster, 1),
          if (budgetUs != null)
            'overBudgetFrames': timings
                .where(
                  (f) =>
                      f.buildDuration.inMicroseconds > budgetUs ||
                      f.rasterDuration.inMicroseconds > budgetUs,
                )
                .length,
          'timingsUs': [
            for (final frame in timings)
              [
                frame.timestampInMicroseconds(FramePhase.vsyncStart),
                frame.buildDuration.inMicroseconds,
                frame.rasterDuration.inMicroseconds,
              ],
          ],
        };
      }

      void mount(Widget child) => runApp(
        ShioriApp(
          key: UniqueKey(),
          locale: const Locale('en'),
          routes: AppRoutes(home: (_) => child),
        ),
      );

      for (final style in [
        PageTurnStyle.curl,
        PageTurnStyle.cover,
        PageTurnStyle.slide,
      ]) {
        current = reader()!;
        check(
          current.content.key == fixtureChapterKey(scenario),
          'Unexpected initial chapter for ${style.name}: ${current.content.key}',
        );
        current.preferences!.update(
          current.preferences!.value.copyWith(pageTurn: style),
        );
        await idle();
        final controller = current.viewportController!;
        final start = controller.capture()!;
        await measure('${style.name}.chapterTurns', () async {
          for (var i = 0; i < 8; i++) {
            await controller.next();
            await idle();
          }
          check(controller.capture() != start, 'Chapter turns did not advance');
        });
        final content = current.content;
        check(
          await controller.restoreConfirmed(
            ReaderPosition(
              contentRevision: content.contentRevision,
              blockKey: content.blocks.last.blockKey,
              blockIndex: content.blocks.length - 1,
              blockFraction: 1,
              chapterFraction: 1,
            ),
            isCurrent: () => true,
          ),
          'Could not reach the chapter boundary',
        );
        final target = fixtureChapterKey(scenario, 1);
        await measure('${style.name}.firstCrossChapter', () async {
          await controller.next();
          await waitFor(() => reader()?.content.key == target);
          await idle();
        });

        final mixed = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.twentyImages),
          title: 'Offline mixed pagination',
          blocks: [
            for (final image
                in fixture.source.data
                    .content(FixtureScenario.twentyImages)
                    .blocks
                    .take(6)) ...[
              ParagraphBlock(text: '星河里的书签 A quiet reading page. ' * 10),
              image,
            ],
            ParagraphBlock(
              text: '字号重排保留语义位置。The reading anchor stays here. ' * 100,
            ),
          ],
        );
        await fixture.settings.save(
          ReaderSettings(controlsHintSeen: true, pageTurn: style),
          cancellation: CancellationSource().token,
        );
        final mixedPreferences = ReaderPreferences(fixture.settings);
        standalonePreferences = mixedPreferences;
        mount(
          ReaderContentView(
            content: mixed,
            settings: fixture.settings,
            preferences: mixedPreferences,
            images: fixture.images,
            viewportController: PagedReaderController(),
            appearanceActive: true,
          ),
        );
        await waitFor(() => identical(reader()?.content, mixed));
        await idle();
        final mixedController = reader()!.viewportController!;
        await measure('${style.name}.mixedTurns', () async {
          final start = mixedController.capture();
          for (var i = 0; i < 8; i++) {
            await mixedController.next();
            await idle();
            final inspection = mixedController.inspectDisplayedPage()!;
            if (inspection.page.fragments.any(
              (f) =>
                  mixed.blocks[inspection.chunks[f.unit].blockIndex]
                      is ImageBlock,
            )) {
              await waitFor(
                () => elements().any(
                  (e) =>
                      e.widget is RawImage &&
                      (e.widget as RawImage).image != null,
                ),
              );
            }
          }
          check(
            mixedController.capture() != start,
            'Mixed turns did not advance',
          );
          check(
            (fixture.source.controls.calls[Operation.media] ?? 0) > 0,
            'No fixture images loaded',
          );
        });
        final anchor = ReaderPosition(
          contentRevision: mixed.contentRevision,
          blockKey: mixed.blocks.last.blockKey,
          blockIndex: mixed.blocks.length - 1,
          blockFraction: .25,
          chapterFraction: .95,
        );
        check(
          await mixedController.restoreConfirmed(anchor, isCurrent: () => true),
          'Could not restore reflow anchor',
        );
        await measure('${style.name}.fontReflow', () async {
          for (final size in [28.0, 20.0, 28.0, 20.0]) {
            final generation = mixedController.layoutGeneration;
            final preferences = reader()!.preferences!;
            preferences.update(preferences.value.copyWith(fontSize: size));
            await waitFor(() => mixedController.layoutGeneration > generation);
            await idle();
            final restored = mixedController.capture()!;
            check(
              restored.blockKey == anchor.blockKey &&
                  (restored.blockFraction - anchor.blockFraction).abs() < .002,
              'Font reflow lost the reading anchor',
            );
          }
        });
        mount(
          BookReaderScreen(
            chapter: fixtureChapterKey(scenario),
            startAtBeginning: true,
            repository: fixture.novels,
            library: fixture.library,
            settings: fixture.settings,
          ),
        );
        await waitFor(() => reader()?.session?.progress != null);
        await idle();
        mixedPreferences.dispose();
        standalonePreferences = null;
      }
      check(errors.isEmpty, 'Framework errors: $errors');
      final report = <String, Object?>{
        'refreshRateHz': refreshRate,
        'logicalSize': [
          view.physicalSize.width / view.devicePixelRatio,
          view.physicalSize.height / view.devicePixelRatio,
        ],
        'results': results,
      };
      debugPrint('PAGINATION_PROFILE_PASS ${results.length} samples');
      return report;
    }
    final content = current.content;
    current.viewportController!.restore(
      ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks.last.blockKey,
        blockIndex: content.blocks.length - 1,
        blockFraction: 1,
        chapterFraction: 1,
      ),
    );
    await waitFor(() => !reader()!.viewportController!.isRestoring);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final session = current.session;
    final viewport = elements().firstWhere(
      (e) =>
          e.widget is PagedReaderViewport &&
          (e.widget as PagedReaderViewport).controller ==
              current.viewportController,
    );
    final results = <String, Object?>{};
    for (final style in [
      PageTurnStyle.curl,
      PageTurnStyle.cover,
      PageTurnStyle.slide,
    ]) {
      current.preferences!.update(
        current.preferences!.value.copyWith(pageTurn: style),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      timings.clear();
      measuring = true;
      for (var repeat = 0; repeat < 3; repeat++) {
        await drag(true, commit: false);
        await drag(true, commit: true);
        await drag(false, commit: false);
        await drag(false, commit: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      measuring = false;
      check(timings.isNotEmpty, 'No native frame timings');
      double percentile(List<double> data, double fraction) {
        data.sort();
        return data[((data.length - 1) * fraction).round()];
      }

      final ui = timings
          .map((f) => f.buildDuration.inMicroseconds / 1000)
          .toList();
      final raster = timings
          .map((f) => f.rasterDuration.inMicroseconds / 1000)
          .toList();
      results[style.name] = {
        'frames': timings.length,
        'uiP95Ms': percentile(ui, .95),
        'rasterP95Ms': percentile(raster, .95),
        'uiMaxMs': percentile(ui, 1),
        'rasterMaxMs': percentile(raster, 1),
      };
    }
    await drag(true, commit: true);
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    await tap(Offset(size.width / 2, size.height * .18));
    check(reader()!.chrome!.value, 'Chrome did not open');
    check(
      elements()
          .map((e) => e.widget)
          .whereType<ReaderBottomBar>()
          .any((bar) => !bar.showProgress),
      'Completion chrome has no dedicated mode',
    );
    await tap(Offset(size.width * .1, size.height * .18));
    check(
      !reader()!.chrome!.value && reader()!.completion != null,
      'Background tap navigated instead of closing chrome',
    );
    check(identical(reader()!.session, session), 'Session replaced');
    check(elements().contains(viewport), 'Real viewport replaced');
    check(
      elements().any((e) => e.widget is ReaderCompletionPage),
      'Completion absent',
    );
    check(errors.isEmpty, 'Framework errors: $errors');
    debugPrint('COMPLETION_PROFILE_PASS ${jsonEncode(results)}');
    return results;
  } catch (error, stack) {
    debugPrint(
      '${pagination ? 'PAGINATION' : 'COMPLETION'}_PROFILE_FAIL $error\n$stack',
    );
    rethrow;
  } finally {
    measuring = false;
    WidgetsBinding.instance.removeTimingsCallback(collect);
    FlutterError.onError = originalError;
    runApp(const SizedBox.shrink());
    await WidgetsBinding.instance.endOfFrame;
    standalonePreferences?.dispose();
    await fixture.close();
  }
}
