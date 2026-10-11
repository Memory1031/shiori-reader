import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_progress_panel.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';

import 'completion_interaction_test.dart' as end;
import 'cross_chapter_drag_test.dart' as book;
import 'full_width_drag_test.dart' as native;
import 'logical_progress_test.dart' as logical;
import 'reader_commands_test.dart' as commands;

final platforms = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.windows,
});

Future<void> screenshot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('SHIORI_CHROME_EVIDENCE')) return;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first)
        .toImage();
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final file = File(
      '.tooling/chrome-turn/${defaultTargetPlatform.name}-$name.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> wheel(WidgetTester tester, double dy) async {
  tester.binding.handlePointerEvent(
    PointerScrollEvent(
      position: const Offset(300, 400),
      scrollDelta: Offset(0, dy),
    ),
  );
  await tester.pump();
}

void main() {
  for (final style in PageTurnStyle.values) {
    testWidgets(
      'native $style hides chrome only after a committed page turn',
      (tester) async {
        final h = native.DragReader();
        await h.open(
          tester,
          size: defaultTargetPlatform == TargetPlatform.windows
              ? const Size(1600, 1000)
              : const Size(390, 844),
        );
        h.settings.value = h.settings.value.copyWith(pageTurn: style);
        h.chrome.value = true;
        await tester.pumpAndSettle();
        final before = h.pages.capture();
        final geometry = tester.getRect(find.byType(PagedReaderViewport));
        final surface = tester.getRect(find.byType(PagedReaderDragSurface));
        final start = Offset(surface.right - 1, surface.center.dy);
        final distance = surface.width * .4;
        if (style == PageTurnStyle.curl) {
          await screenshot(tester, 'native-open');
        }

        final cancelled = await native.heldDrag(
          tester,
          start,
          delta: -distance,
        );
        expect(h.chrome.value, isTrue);
        expect(h.pages.capture(), before);
        await cancelled.cancel();
        await tester.pumpAndSettle();
        expect(h.chrome.value, isTrue);
        expect(h.pages.capture(), before);

        final rebound = await native.heldDrag(tester, start, delta: -35);
        await tester.pump(const Duration(milliseconds: 150));
        await rebound.up();
        await tester.pumpAndSettle();
        expect(h.chrome.value, isTrue);
        expect(h.pages.capture(), before);
        if (style == PageTurnStyle.curl) {
          await screenshot(tester, 'native-rebound');
        }

        final forward = await native.heldDrag(tester, start, delta: -distance);
        expect(h.chrome.value, isTrue);
        await tester.pump(const Duration(milliseconds: 150));
        await forward.up();
        await tester.pumpAndSettle();
        final next = h.pages.capture();
        expect(next, isNot(before));
        expect(h.chrome.value, isFalse);
        expect(find.byType(ReaderToolbars), findsNothing);
        expect(tester.getRect(find.byType(PagedReaderViewport)), geometry);
        if (style == PageTurnStyle.curl) {
          await screenshot(tester, 'native-committed');
        }

        h.chrome.value = true;
        await tester.pumpAndSettle();
        final backward = await native.heldDrag(
          tester,
          Offset(surface.left + 1, surface.center.dy),
          delta: distance,
        );
        expect(h.chrome.value, isTrue);
        await backward.up();
        await tester.pumpAndSettle();
        expect(h.pages.capture(), before);
        expect(h.chrome.value, isFalse);

        h.chrome.value = true;
        h.pages.restore(next!);
        await tester.pumpAndSettle();
        expect(
          h.chrome.value,
          isTrue,
          reason: 'an explicit restore is not a turn',
        );
        expect(h.pages.capture(), next);
        expect(tester.takeException(), isNull);
        await h.close(tester);
      },
      variant: platforms,
    );
  }

  testWidgets(
    'native keyboard and wheel hide chrome after success',
    (tester) async {
      final reader = await commands.pumpReader(tester, chrome: true);
      for (final key in [
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.pageUp,
      ]) {
        if (!commands.chromeVisible()) {
          await commands.chord(tester, LogicalKeyboardKey.f2);
        }
        final before = reader.fraction;
        await commands.chord(tester, key, settle: false);
        expect(commands.chromeVisible(), isTrue);
        await tester.pumpAndSettle();
        expect(reader.fraction, isNot(before));
        expect(commands.chromeVisible(), isFalse);
      }
      await commands.chord(tester, LogicalKeyboardKey.f2);
      final before = reader.fraction;
      await wheel(tester, 100);
      await tester.pumpAndSettle();
      expect(reader.fraction, greaterThan(before));
      expect(commands.chromeVisible(), isFalse);
    },
    variant: commands.windows,
  );

  for (final direction in [1, -1]) {
    testWidgets(
      'cross-chapter $direction preserves chrome on cancel and rebound, hides on commit',
      (tester) async {
        final h = book.Harness();
        await h.open(tester, index: direction > 0 ? 0 : 1);
        final old = book.active(tester);
        final chrome = old.chrome!;
        chrome.value = true;
        await tester.pumpAndSettle();
        final cancelled = await book.drag(tester, direction);
        expect(chrome.value, isTrue);
        await cancelled.cancel();
        await tester.pumpAndSettle();
        expect(chrome.value, isTrue);
        expect(book.active(tester).session, same(old.session));

        final rebound = await book.drag(tester, direction, distance: 65);
        await tester.pump(const Duration(milliseconds: 150));
        await rebound.up();
        await tester.pumpAndSettle();
        expect(chrome.value, isTrue);
        expect(book.active(tester).session, same(old.session));
        if (direction > 0) await screenshot(tester, 'boundary-rebound');

        final committed = await book.drag(tester, direction);
        expect(chrome.value, isTrue);
        await committed.up();
        await book.layoutFrames(tester);
        expect(chrome.value, isTrue, reason: 'settling has not committed yet');
        await tester.pumpAndSettle();
        expect(book.active(tester).content.key, h.key(direction > 0 ? 1 : 0));
        expect(chrome.value, isFalse);
        expect(find.byType(ReaderToolbars), findsNothing);
        if (direction > 0) await screenshot(tester, 'boundary-committed');
        expect(tester.takeException(), isNull);
        await h.close(tester);
      },
      variant: platforms,
    );
  }

  for (final outcome in ['success', 'failure', 'cancel']) {
    testWidgets('waiting chapter $outcome preserves chrome until success', (
      tester,
    ) async {
      final h = book.Harness();
      final pending = Completer<Result<LoadResult<ChapterContent>>>();
      h.repository.holds[h.key(1)] = pending;
      await h.open(tester);
      final old = book.active(tester);
      old.chrome!.value = true;
      await tester.pumpAndSettle();
      final gesture = await book.drag(tester, 1);
      await gesture.up();
      await book.layoutFrames(tester);
      expect(old.chrome!.value, isTrue);
      if (outcome == 'cancel') {
        await tester.tap(find.byKey(const ValueKey('cancel-chapter-turn')));
        await tester.pumpAndSettle();
      }
      pending.complete(
        outcome == 'failure'
            ? Failure(
                AppFailure(
                  kind: FailureKind.parse,
                  operation: Operation.chapter,
                ),
              )
            : h.repository.result(h.key(1)),
      );
      await tester.pumpAndSettle();
      expect(old.chrome!.value, outcome != 'success');
      expect(
        book.active(tester).content.key,
        h.key(outcome == 'success' ? 1 : 0),
      );
      expect(tester.takeException(), isNull);
      await h.close(tester);
    });
  }

  for (final input in ['keyboard', 'wheel']) {
    testWidgets(
      'cross-chapter $input hides chrome at the committed switch',
      (tester) async {
        final h = book.Harness();
        await h.open(tester);
        final chrome = book.active(tester).chrome!;
        chrome.value = true;
        await tester.pumpAndSettle();
        if (input == 'keyboard') {
          await commands.chord(
            tester,
            LogicalKeyboardKey.pageDown,
            settle: false,
          );
        } else {
          await wheel(tester, 100);
        }
        expect(chrome.value, isTrue);
        await tester.pumpAndSettle();
        expect(book.active(tester).content.key, h.key(1));
        expect(chrome.value, isFalse);
        await h.close(tester);
      },
      variant: commands.windows,
    );
  }

  testWidgets('an unavailable previous page preserves chrome', (tester) async {
    final h = book.Harness();
    await h.open(tester);
    final old = book.active(tester);
    old.chrome!.value = true;
    await tester.pumpAndSettle();
    await commands.chord(tester, LogicalKeyboardKey.pageUp);
    expect(old.chrome!.value, isTrue);
    expect(book.active(tester).session, same(old.session));
    await h.close(tester);
  }, variant: commands.windows);

  testWidgets('online progress chapter steps preserve chrome', (tester) async {
    final h = book.Harness();
    await h.open(tester);
    for (final (label, target) in [
      ('Next chapter', h.key(1)),
      ('Previous chapter', h.key(0)),
    ]) {
      await commands.chord(tester, LogicalKeyboardKey.keyG, control: true);
      expect(find.byType(ReaderProgressPanel), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(book.active(tester).content.key, target);
      expect(book.active(tester).chrome!.value, isTrue);
    }
    await h.close(tester);
  }, variant: commands.windows);

  testWidgets(
    'local directory and progress navigation preserve chrome',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final h = await logical.mount(tester);
      await logical.openProgress(tester);
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(.8);
      await tester.pumpAndSettle();
      expect(h.view(tester).content.key, h.book.chapters[2].key);
      expect(h.view(tester).chrome!.value, isTrue);

      await logical.openProgress(tester);
      final session = h.view(tester).session;
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(1);
      await tester.pumpAndSettle();
      expect(h.view(tester).session, same(session));
      expect(h.view(tester).chrome!.value, isTrue);
      await logical.closeOverlay(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(ReaderBottomBar),
          matching: find.byIcon(Icons.list),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second logical'));
      await tester.pumpAndSettle();
      expect(h.view(tester).content.key, h.book.chapters[3].key);
      expect(h.view(tester).chrome!.value, isTrue);
      await screenshot(tester, 'directory-navigation');
      await logical.openProgress(tester);
      await tester.tap(find.text('Previous chapter'));
      await tester.pumpAndSettle();
      expect(h.view(tester).content.key, h.book.chapters.first.key);
      expect(h.view(tester).chrome!.value, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'completion turns preserve chrome on cancel and hide on success',
    (tester) async {
      final h = end.Harness();
      await h.open(tester);
      final chrome = h.view(tester).chrome!;
      chrome.value = true;
      await tester.pumpAndSettle();
      final cancelled = await end.drag(tester, true);
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(chrome.value, isTrue);
      expect(h.view(tester).completion, isNull);
      final entering = await end.drag(tester, true);
      expect(chrome.value, isTrue);
      await entering.up();
      await tester.pumpAndSettle();
      expect(h.view(tester).completion, isNotNull);
      expect(chrome.value, isFalse);
      chrome.value = true;
      await tester.pumpAndSettle();
      final returning = await end.drag(tester, false);
      expect(chrome.value, isTrue);
      await returning.up();
      await tester.pumpAndSettle();
      expect(h.view(tester).completion, isNull);
      expect(chrome.value, isFalse);
      await h.close(tester);
    },
    variant: platforms,
  );
}
