// Offline completion probe, dispatched by the shared profile entry.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming;

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

Future<void> runCompletionProbe() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fixture = FixtureEnvironment(scenario: FixtureScenario.shortChapter);
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
        throw StateError('Completion probe timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  ReaderContentView? reader() => elements()
      .map((e) => e.widget)
      .whereType<ReaderContentView>()
      .where((v) => v.appearanceActive == true)
      .firstOrNull;
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
            chapter: fixture.source.data
                .catalog(FixtureScenario.shortChapter)
                .flatChapters
                .last
                .key,
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
  } catch (error, stack) {
    debugPrint('COMPLETION_PROFILE_FAIL $error\n$stack');
  } finally {
    measuring = false;
    WidgetsBinding.instance.removeTimingsCallback(collect);
    FlutterError.onError = originalError;
  }
}
