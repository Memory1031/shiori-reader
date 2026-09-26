import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/novel_detail/desktop_detail.dart';
import 'package:shiori/features/novel_detail/detail_screen.dart';
import 'package:shiori/features/novel_detail/detail_sections.dart';
import 'package:shiori/shared/widgets/state_views.dart';

import '../desktop_shell_test.dart' show ShellHarness;
import 'desktop_detail_test.dart';

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

ScrollableState _scroll(WidgetTester tester, Finder viewport) =>
    tester.state<ScrollableState>(
      find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
    );

Future<void> _wheel(WidgetTester tester, Offset point, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: point,
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'expanded synopsis remains visible with the same scroll state across column reflow',
    (tester) async {
      final repo = Requests(
        book(
          online,
          text: List.generate(40, (i) => 'Synopsis paragraph $i.').join('\n'),
          tagList: const [],
        ),
      );
      final h = DetailHarness(tester, repo);
      await h.pump(width: 1920);
      await tester.tap(h.key('detail-synopsis-toggle'));
      await tester.pumpAndSettle();
      final view = h.key('detail-scroll');
      final scroll = _scroll(tester, view);
      final position = scroll.position;
      position.jumpTo(250);
      await tester.pumpAndSettle();
      for (final width in [1920.0, 900.0, 1199.0, 1200.0, 1920.0]) {
        await h.resize(width);
        expect(_scroll(tester, view), same(scroll));
        // GlobalKey reparenting triggers didChangeDependencies; Flutter may
        // replace ScrollPosition while absorbing its offset into the new one.
        expect(scroll.position.pixels, closeTo(250, .01));
        expect(find.text(h.l.detailShowLess), findsOneWidget);
        // Reflow changes header height; assert semantic content remains in view,
        // rather than equating an unchanged offset with correct visibility.
        expect(
          h.rect(find.byType(DetailSynopsis)).overlaps(h.rect(view)),
          isTrue,
        );
        expect(repo.details, [ReadMode.cacheFirst]);
        expect(repo.catalogs, [ReadMode.cacheOnly]);
      }
      await h.close();
    },
    variant: _windows,
  );

  for (final width in [900.0, 1920.0]) {
    testWidgets(
      'Detail $width margins and edge scrollbar drive main, side stays independent',
      (tester) async {
        final h = DetailHarness(tester, Requests(book(online)));
        await h.pump(width: width, height: 420);
        final view = h.key('detail-scroll');
        final main = _scroll(tester, view).position;
        final rect = h.rect(view);
        expect(rect.left, h.offset);
        expect(rect.right, width);
        final bar = h.rect(find.byType(DesktopDetailBar));
        expect(bar.left - h.offset, closeTo(width - bar.right, .01));
        final side = h.layout.columns
            ? _scroll(tester, h.key('detail-side')).position
            : null;
        for (final x in [h.offset + 4, width - 20]) {
          final before = main.pixels;
          await _wheel(tester, Offset(x, rect.center.dy), 80);
          expect(main.pixels, greaterThan(before));
          if (side != null) expect(side.pixels, 0);
        }
        main.jumpTo(0);
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset(width - 4, rect.top + 15));
        await mouse.moveTo(Offset(width - 4, rect.top + 16));
        await tester.pumpAndSettle();
        await mouse.down(Offset(width - 4, rect.top + 16));
        await mouse.moveBy(const Offset(0, 100));
        await tester.pump();
        await mouse.up();
        await tester.pumpAndSettle();
        expect(main.pixels, greaterThan(0));
        await mouse.removePointer();
        if (side != null) {
          expect(side.maxScrollExtent, greaterThan(0));
          final before = main.pixels;
          await _wheel(tester, h.rect(h.key('detail-side')).center, 80);
          expect(side.pixels, greaterThan(0));
          expect(main.pixels, before);
          expect(
            find.descendant(
              of: h.key('detail-side'),
              matching: find.byType(Scrollbar),
            ),
            findsOneWidget,
          );
        }
        expect(h.repo.details, [ReadMode.cacheFirst]);
        expect(tester.takeException(), isNull);
        await h.close();
      },
      variant: _windows,
    );
  }

  testWidgets(
    'bounded Shell Detail uses Shell gutter, preserves route and column state',
    (tester) async {
      final h = ShellHarness(tester);
      await h.pump(size: const Size(1920, 720), shellWidth: 900);
      await h.search();
      await h.openResult();
      final workspace = h.workspace;
      final detail = tester.element(find.byType(DetailScreen));
      final page = tester.state(find.byType(DesktopDetail));
      final viewport = tester.element(
        find.byKey(const ValueKey('detail-scroll')),
      );
      expect(MediaQuery.sizeOf(detail).width, 1920);
      for (final width in [
        900.0,
        839.0,
        840.0,
        1199.0,
        1200.0,
        1199.0,
        1920.0,
      ]) {
        await h.pump(size: const Size(1920, 720), shellWidth: width);
        expect(h.workspace, same(workspace));
        expect(tester.element(find.byType(DetailScreen)), same(detail));
        expect(tester.state(find.byType(DesktopDetail)), same(page));
        expect(
          tester.element(find.byKey(const ValueKey('detail-scroll'))),
          same(viewport),
        );
        final nav = width < 840
            ? 0.0
            : width < 1200
            ? 72.0
            : 232.0;
        final gutter = width < 1200 ? 24.0 : 32.0;
        final frame = (width - nav - 2 * gutter).clamp(0, 1040);
        final toolbar = tester.getRect(find.byType(DesktopDetailBar));
        expect(toolbar.width, frame);
        expect(toolbar.left, closeTo(nav + (width - nav - frame) / 2, .01));
        expect(
          tester.getRect(find.byKey(const ValueKey('detail-scroll'))).right,
          width,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('detail-back')));
      await tester.pumpAndSettle();
      expect(h.workspace.canPop(), isFalse);
      await h.close();
    },
    variant: _windows,
  );

  for (final width in [900.0, 1920.0]) {
    testWidgets(
      'RTL Detail $width centers frame and preserves directional columns',
      (tester) async {
        final h = DetailHarness(tester, Requests(book(online)), host: Host.root)
          ..direction = TextDirection.rtl;
        await h.pump(width: width);
        final bar = h.rect(find.byType(DesktopDetailBar));
        expect(bar.left, closeTo(width - bar.right, .01));
        expect(h.rect(h.key('detail-back')).right, closeTo(bar.right, .01));
        expect(h.rect(h.key('detail-more')).left, closeTo(bar.left, .01));
        expect(h.rect(find.byType(DetailCover)).right, closeTo(bar.right, .01));
        final info = h.rect(find.byType(DetailBookInfo));
        expect(info.left, closeTo(bar.left, .01));
        if (h.layout.columns) {
          expect(info.right, closeTo(bar.right - h.layout.side - 40, .01));
        }
        expect(tester.takeException(), isNull);
        await h.close();
      },
      variant: _windows,
    );
  }

  testWidgets(
    'loading, failure, stale and refresh notices share centered Detail frame',
    (tester) async {
      final initial = Completer<Result<LoadResult<NovelDetail>>>();
      final repo = Requests(book(online))..detailResult = (_) => initial.future;
      final h = DetailHarness(tester, repo);
      await h.pump(width: 1920, settle: false);
      void aligned(Finder finder) {
        final bar = h.rect(find.byType(DesktopDetailBar));
        final rect = h.rect(finder);
        expect(rect.left, closeTo(bar.left, .01));
        expect(rect.right, closeTo(bar.right, .01));
      }

      aligned(find.byType(LoadingView));
      initial.complete(Failure(detailDown));
      await tester.pumpAndSettle();
      aligned(find.byType(FailureView));
      repo.detailResult = (_) async => Success(
        LoadResult(
          value: book(online),
          origin: LoadOrigin.local,
          fetchedAt: DateTime.utc(2026),
          isStale: true,
        ),
      );
      await tester.tap(find.text(h.l.retryAction));
      await tester.pumpAndSettle();
      aligned(find.text(h.l.detailStale));
      final refresh = Completer<Result<LoadResult<NovelDetail>>>();
      repo.detailResult = (_) => refresh.future;
      await tester.tap(h.key('detail-more'));
      await tester.pumpAndSettle();
      await tester.tap(h.key('detail-refresh'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      aligned(find.byType(LinearProgressIndicator));
      refresh.complete(Failure(detailDown));
      await tester.pumpAndSettle();
      aligned(find.byType(FailureView));
      aligned(find.text(h.l.detailStale));
      expect(tester.takeException(), isNull);
      await h.close();
    },
    variant: _windows,
  );
}
