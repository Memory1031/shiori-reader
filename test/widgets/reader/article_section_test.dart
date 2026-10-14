import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/article_contents.dart';
import 'package:shiori/features/reader/reader_contents.dart';
import 'package:shiori/features/reader/reader_contents_session.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_progress_panel.dart';
import 'package:shiori/features/novel_detail/catalog_view.dart';
import 'package:shiori/shared/widgets/catalog_browsing.dart';

import 'reader_contents_session_test.dart' as browsing;
import 'full_width_drag_test.dart' show DragReader;
import 'progress_preview_test.dart' show dragProgress;

ChapterContent content({int count = 3000, String title = 'Article'}) =>
    ChapterContent(
      key: browsing.key(1000),
      title: title,
      blocks: [
        ParagraphBlock(text: 'Foreword before any section.'),
        for (var i = 0; i < count; i++) ...[
          HeadingBlock(
            text: 'Section $i 相同标题 ${'Long heading ' * (i % 4)}',
            level: 2,
          ),
          ParagraphBlock(text: 'Synthetic section $i reading text。' * 10),
        ],
      ],
    );

ReaderPosition at(ChapterContent body, int block) => ReaderPosition(
  contentRevision: body.contentRevision,
  blockKey: body.blocks[block].blockKey,
  blockIndex: block,
  blockFraction: 0,
  chapterFraction: ReaderPosition.fractionFor(
    blockIndex: block,
    blockFraction: 0,
    blockCount: body.blocks.length,
  ),
);

List<ListTile> selected(WidgetTester tester) => tester
    .widgetList<ListTile>(find.byType(ListTile))
    .where((tile) => tile.selected)
    .toList();
ScrollPosition scroll(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).last).position;
Finder row(ChapterContent body, int block) =>
    find.byKey(ValueKey(body.blocks[block].blockKey));
ValueListenable<ReaderPosition?> stablePosition(WidgetTester tester) =>
    tester
            .widgetList<AnimatedBuilder>(
              find.descendant(
                of: find.byType(ReaderContentsPanel),
                matching: find.byType(AnimatedBuilder),
              ),
            )
            .firstWhere((w) => w.animation is ValueListenable<ReaderPosition?>)
            .animation
        as ValueListenable<ReaderPosition?>;

class SectionPanel {
  SectionPanel(this.body, ReaderPosition? position)
    : current = ValueNotifier(position);
  ChapterContent body;
  final ValueNotifier<ReaderPosition?> current;
  final memory = CatalogBrowsingState();
  final boundary = GlobalKey();
  final navigator = GlobalKey<NavigatorState>();
  ReaderPosition? choice;
  Future<void> mount(
    WidgetTester tester, {
    bool shown = true,
    double scale = 1,
    bool dark = false,
    String language = 'en',
    Size size = const Size(400, 700),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ShioriApp(
          navigatorKey: navigator,
          locale: Locale(language),
          overlayBuilder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(brightness: dark ? Brightness.dark : Brightness.light),
              child: child,
            ),
          ),
          routes: AppRoutes(
            home: (context) => Scaffold(
              body: shown
                  ? ReaderContentsPanel(
                      layers: [
                        articleContentsLayer(
                          context,
                          body,
                          current: current,
                          browsing: memory,
                          onSelect: (target) => choice = target,
                        ),
                      ],
                      onDone: ([then]) => then?.call(),
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void cleanup(WidgetTester tester) {
    addTearDown(tester.view.reset);
    addTearDown(current.dispose);
  }
}

void main() {
  for (final index in [0, 1500, 2999]) {
    testWidgets(
      'initial current section $index is visible and lazily positioned',
      (tester) async {
        final body = content(), panel = SectionPanel(content(), null);
        panel.body = body;
        panel.current.value = at(body, 1 + index * 2);
        panel.cleanup(tester);
        await panel.mount(tester);
        expect(
          selected(tester).single.key,
          ValueKey(body.blocks[1 + index * 2].blockKey),
        );
        expect(row(body, 1 + index * 2).hitTestable(), findsOneWidget);
        expect(find.byType(ListTile).evaluate().length, lessThan(40));
        expect(
          panel.memory.position,
          isNull,
          reason: 'automatic positioning is not manual browsing',
        );
        final bounds = tester.getRect(find.byType(Scrollable).last);
        if (index == 1500) {
          expect(
            tester.getTopLeft(row(body, 1 + index * 2)).dy - bounds.top,
            closeTo(bounds.height / 3, .01),
          );
        }
        final position = scroll(tester);
        expect(position.maxScrollExtent, greaterThan(0));
        position.jumpTo(position.minScrollExtent);
        await tester.pumpAndSettle();
        expect(row(body, 1).hitTestable(), findsOneWidget);
        for (var n = 0; n < 10; n++) {
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          if (row(body, 5999).evaluate().isNotEmpty &&
              (tester.getBottomLeft(row(body, 5999)).dy - bounds.bottom).abs() <
                  .01) {
            break;
          }
        }
        expect(row(body, 5999).hitTestable(), findsOneWidget);
        expect(
          tester.getBottomLeft(row(body, 5999)).dy,
          closeTo(bounds.bottom, .01),
          reason: 'no empty trailing viewport',
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'unknown position can locate once, then manual browsing wins over highlight updates',
    (tester) async {
      final body = content(), panel = SectionPanel(content(), null);
      panel.body = body;
      panel.cleanup(tester);
      await panel.mount(tester);
      expect(selected(tester), isEmpty);
      expect(scroll(tester).pixels, 0);
      panel.current.value = at(body, 3001);
      await tester.pumpAndSettle();
      expect(row(body, 3001).hitTestable(), findsOneWidget);
      scroll(tester).jumpTo(scroll(tester).pixels + 1800);
      await tester.pumpAndSettle();
      final anchor = browsing.visibleRow(tester),
          offset = scroll(tester).pixels;
      panel.current.value = at(body, 3003);
      await tester.pumpAndSettle();
      expect(scroll(tester).pixels, offset);
      expect(browsing.visibleRow(tester), anchor);
      await panel.mount(tester, shown: false);
      await panel.mount(tester);
      expect(browsing.visibleRow(tester).key, anchor.key);
      expect(browsing.visibleRow(tester).top, closeTo(anchor.top, .01));
      expect(row(body, 3003).hitTestable(), findsNothing);
      panel.memory.configure(
        panel.memory.attach(),
        'invalidated data',
        'layout',
      );
      await panel.mount(tester, shown: false);
      await panel.mount(tester);
      expect(row(body, 3003).hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'a late first anchor waits for an uncovered contents route before locating',
    (tester) async {
      final body = content(), panel = SectionPanel(content(), null);
      panel.body = body;
      panel.cleanup(tester);
      await panel.mount(tester);
      final position = scroll(tester);
      unawaited(
        panel.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      panel.current.value = at(body, 3001);
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
      panel.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(row(body, 3001).hitTestable(), findsOneWidget);
      expect(panel.memory.position, isNull);
    },
  );

  testWidgets(
    'foreword, stale revision and content replacement never use an old selected index',
    (tester) async {
      final body = content(count: 40),
          panel = SectionPanel(content(count: 40), null);
      panel.body = body;
      panel.cleanup(tester);
      panel.current.value = at(body, 0);
      await panel.mount(tester);
      expect(selected(tester), isEmpty);
      expect(scroll(tester).pixels, 0);
      panel.current.value = at(body, 31);
      await tester.pumpAndSettle();
      expect(
        scroll(tester).pixels,
        0,
        reason:
            'no live following after opening with a confirmed foreword anchor',
      );
      await panel.mount(tester, shown: false);
      panel.body = content(count: 4, title: 'Replacement');
      await panel.mount(tester);
      expect(selected(tester), isEmpty);
      expect(scroll(tester).pixels, 0);
      panel.current.value = at(panel.body, 5);
      await tester.pumpAndSettle();
      expect(
        selected(tester).single.key,
        ValueKey(panel.body.blocks[5].blockKey),
      );
      expect(row(panel.body, 5).hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'selected semantics, title alignment, touch size and original target selection',
    (tester) async {
      final body = content(count: 12),
          panel = SectionPanel(content(count: 12), null);
      panel.body = body;
      panel.current.value = at(body, 11);
      panel.cleanup(tester);
      final semantics = tester.ensureSemantics();
      await panel.mount(tester, size: const Size(390, 844), scale: 1.5);
      expect(
        tester.getSemantics(row(body, 11)),
        matchesSemantics(
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          label: articleContents(body)[5].title,
        ),
      );
      final highlightedTitle = find.descendant(
        of: row(body, 11),
        matching: find.byType(Text),
      );
      final nextTitle = find.descendant(
        of: row(body, 13),
        matching: find.byType(Text),
      );
      expect(
        tester.getTopLeft(highlightedTitle).dx,
        tester.getTopLeft(nextTitle).dx,
      );
      expect(tester.getSize(row(body, 11)).height, greaterThanOrEqualTo(48));
      await tester.tap(row(body, 13));
      expect(panel.choice, at(body, 13));
      expect(
        selected(tester).single.key,
        ValueKey(body.blocks[11].blockKey),
        reason: 'a click alone does not confirm navigation',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'cancelled and confirmed page previews use only committed page-group anchors',
    (tester) async {
      final body = content(count: 50),
          reader = DragReader(content: content(count: 50));
      await reader.open(tester);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        reader.chrome.dispose();
      });
      final view = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView),
      );
      // Capture the production layer's stable-position input before interacting.
      reader.chrome.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.list));
      await tester.pumpAndSettle();
      final stable =
          tester
                  .widgetList<AnimatedBuilder>(
                    find.descendant(
                      of: find.byType(ReaderContentsPanel),
                      matching: find.byType(AnimatedBuilder),
                    ),
                  )
                  .firstWhere(
                    (w) => w.animation is ValueListenable<ReaderPosition?>,
                  )
                  .animation
              as ValueListenable<ReaderPosition?>;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      reader.chrome.value = false;
      await tester.pumpAndSettle();
      final source = reader.pages.capture()!;
      var gesture = await dragProgress(tester, -160);
      expect(reader.pages.capture(), source);
      expect(stable.value, source);
      // A covered reader's menu projection reads the same stable signal.
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(reader.pages.capture(), source);
      expect(stable.value, source);
      gesture = await dragProgress(tester, -260);
      expect(stable.value, source);
      await gesture.up();
      await tester.pumpAndSettle();
      final target = reader.pages.capture()!;
      expect(target.blockIndex, greaterThan(source.blockIndex));
      expect(stable.value, target);
      reader.chrome.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.list));
      await tester.pumpAndSettle();
      expect(
        selected(tester).single.key,
        ValueKey(
          view
              .content
              .blocks[articleContents(body)[currentArticleSection(
                    body,
                    articleContents(body),
                    target,
                  )!]
                  .position
                  .blockIndex]
              .blockKey,
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'production heading navigation and successful/failed chapter switches retain #5 priorities',
    (tester) async {
      final reader = browsing.OnlineReader();
      await reader.mount(tester);
      final source = browsing.view(tester), body = source.content;
      source.viewportController!.restore(at(body, 70));
      await tester.pumpAndSettle();
      await browsing.open(tester);
      expect(selected(tester).single.key, ValueKey(body.blocks[70].blockKey));
      final top = browsing.visibleRow(tester);
      await browsing.browse(tester, scroll(tester).pixels + 1000);
      final anchor = browsing.visibleRow(tester);
      await browsing.layer(tester, ReaderContentsKind.book);
      await browsing.layer(tester, ReaderContentsKind.article);
      expect(browsing.visibleRow(tester).key, anchor.key);
      await browsing.close(tester);
      source.viewportController!.restore(at(body, 72));
      await tester.pumpAndSettle();
      await browsing.open(tester);
      expect(
        browsing.visibleRow(tester).key,
        anchor.key,
        reason: 'normal same-chapter position changes keep manual browsing',
      );
      await browsing.close(tester);
      reader.repository
        ..blocked = browsing.key(1001)
        ..fail = true;
      source.actions.nextChapter!();
      await tester.pumpAndSettle();
      expect(browsing.view(tester).content.key, body.key);
      await tester.pump(const Duration(seconds: 5));
      await browsing.open(tester);
      expect(browsing.visibleRow(tester).key, anchor.key);
      await browsing.close(tester);
      reader.repository.fail = false;
      await browsing.open(tester);
      await browsing.layer(tester, ReaderContentsKind.book);
      tester
          .widget<CatalogView>(find.byType(CatalogView))
          .onSelect(browsing.key(1002));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await browsing.open(tester);
      await browsing.layer(tester, ReaderContentsKind.article);
      final next = browsing.view(tester).content;
      expect(selected(tester).single.key, ValueKey(next.blocks.first.blockKey));
      expect(
        browsing.visibleRow(tester).key,
        ValueKey(next.blocks.first.blockKey),
      );
      expect(top.key, isNot(anchor.key));
    },
  );

  testWidgets(
    'two headings on one visible page use the group start and confirmed explicit anchors',
    (tester) async {
      final body = ChapterContent(
        key: browsing.key(1000),
        title: 'Same page',
        blocks: [
          ParagraphBlock(text: 'Foreword'),
          HeadingBlock(text: 'First', level: 2),
          ParagraphBlock(text: 'Short paragraph'),
          HeadingBlock(text: 'Second', level: 2),
          ParagraphBlock(text: 'Final paragraph'),
        ],
      );
      final reader = DragReader(content: body);
      await reader.open(tester);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        reader.chrome.dispose();
      });
      expect(find.text('First').hitTestable(), findsOneWidget);
      expect(find.text('Second').hitTestable(), findsOneWidget);
      reader.chrome.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.list));
      await tester.pumpAndSettle();
      expect(
        selected(tester),
        isEmpty,
        reason: 'the page group starts in the foreword',
      );
      await tester.tap(row(body, 1));
      await tester.pumpAndSettle();
      expect(reader.pages.capture()!.blockKey, body.blocks[1].blockKey);
      reader.chrome.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.list));
      await tester.pumpAndSettle();
      expect(selected(tester).single.key, ValueKey(body.blocks[1].blockKey));
      await tester.tap(row(body, 3));
      await tester.pumpAndSettle();
      reader.chrome.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.list));
      await tester.pumpAndSettle();
      expect(selected(tester).single.key, ValueKey(body.blocks[3].blockKey));
    },
  );

  testWidgets(
    'reflow retains the semantic section; progress preview cancels and confirmed seek invalidates browsing',
    (tester) async {
      final reader = browsing.OnlineReader();
      await reader.mount(tester);
      final source = browsing.view(tester), body = source.content;
      source.viewportController!.restore(at(body, 70));
      await tester.pumpAndSettle();
      await browsing.open(tester);
      final stable = stablePosition(tester);
      await browsing.browse(tester, scroll(tester).pixels + 600);
      await browsing.close(tester);
      final preferences = source.preferences!;
      preferences.update(
        preferences.value.copyWith(fontSize: preferences.value.fontSize + 4),
      );
      await tester.pumpAndSettle();
      expect(stable.value!.blockKey, body.blocks[70].blockKey);
      await browsing.open(tester);
      expect(
        row(body, 70).hitTestable(),
        findsNothing,
        reason: 'body typography does not invalidate valid directory browsing',
      );
      await browsing.close(tester);
      tester.view.physicalSize = const Size(450, 800);
      await tester.pumpAndSettle();
      await browsing.open(tester);
      expect(
        row(body, 70).hitTestable(),
        findsOneWidget,
        reason: 'layout invalidation permits initial location again',
      );
      await browsing.browse(tester, scroll(tester).pixels + 600);
      final memory = source.contentsSession!.article;
      await browsing.close(tester);
      source.chrome!.value = true;
      await tester.pumpAndSettle();
      final progress = find
          .byWidgetPredicate(
            (w) =>
                w is Text && RegExp(r'^Chapter \d+%$').hasMatch(w.data ?? ''),
          )
          .hitTestable();
      await tester.tap(progress);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderProgressPanel), findsOneWidget);
      tester.widget<Slider>(find.byType(Slider)).onChanged!(.8);
      await tester.pumpAndSettle();
      expect(stable.value!.blockKey, body.blocks[70].blockKey);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(source.contentsSession!.article, same(memory));
      await tester.tap(progress);
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(.8);
      await tester.pumpAndSettle();
      final target = source.viewportController!.capture()!;
      expect(target.blockIndex, greaterThan(70));
      expect(stable.value, target);
      expect(source.contentsSession!.article, isNot(same(memory)));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await browsing.open(tester);
      final entry = articleContents(
        body,
      )[currentArticleSection(body, articleContents(body), target)!];
      expect(selected(tester).single.key, ValueKey(entry.position.blockKey));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'covered and retired readers reject late candidate and heading-selection callbacks',
    (tester) async {
      final reader = browsing.OnlineReader();
      await reader.mount(tester);
      final source = browsing.view(tester), body = source.content;
      source.viewportController!.restore(at(body, 70));
      await tester.pumpAndSettle();
      await browsing.open(tester);
      final stable = stablePosition(tester);
      final oldChoice = selected(tester).single.onTap!;
      await browsing.close(tester);
      reader.repository
        ..blocked = browsing.key(1001)
        ..pending = Completer<void>();
      source.actions.nextChapter!();
      await tester.pump(const Duration(milliseconds: 50));
      expect(stable.value!.blockKey, body.blocks[70].blockKey);
      unawaited(
        reader.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      reader.repository.pending!.complete();
      await tester.pumpAndSettle();
      reader.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(browsing.view(tester).content.key, body.key);
      await browsing.open(tester);
      expect(selected(tester).single.key, ValueKey(body.blocks[70].blockKey));
      await browsing.close(tester);
      source.actions.leave!();
      await tester.pumpAndSettle();
      oldChoice();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderContentView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scene in [
    ('android-zh', TargetPlatform.android, Size(400, 800), 1.0, false, 'zh'),
    ('ios-en', TargetPlatform.iOS, Size(390, 844), 1.4, true, 'en'),
    ('windows-narrow', TargetPlatform.windows, Size(600, 700), 1.5, true, 'zh'),
    ('windows-wide', TargetPlatform.windows, Size(1500, 900), 1.0, false, 'en'),
  ]) {
    testWidgets(
      'render current section ${scene.$1}',
      (tester) async {
        final font = Platform.environment['SHIORI_CONTENTS_FONT'],
            icons = Platform.environment['SHIORI_CONTENTS_ICONS'];
        await tester.runAsync(() async {
          if (font != null) {
            final bytes = ByteData.sublistView(await File(font).readAsBytes());
            for (final family in [
              'Roboto',
              'Microsoft YaHei UI',
              'CupertinoSystemText',
              'CupertinoSystemDisplay',
            ]) {
              await (FontLoader(family)..addFont(Future.value(bytes))).load();
            }
          }
          if (icons != null) {
            await (FontLoader('MaterialIcons')..addFont(
                  File(icons).readAsBytes().then(ByteData.sublistView),
                ))
                .load();
          }
        });
        final reader = browsing.OnlineReader();
        reader.repository.chapters[browsing.key(1000)] = content(count: 100);
        await reader.mount(
          tester,
          size: scene.$3,
          scale: scene.$4,
          dark: scene.$5,
          language: scene.$6,
        );
        final body = browsing.view(tester).content;
        browsing.view(tester).viewportController!.restore(at(body, 71));
        await tester.pumpAndSettle();
        await browsing.open(tester);
        expect(selected(tester).single.key, ValueKey(body.blocks[71].blockKey));
        await browsing.screenshot(
          tester,
          reader.boundary,
          '${scene.$1}-current',
        );
        await browsing.browse(tester, scroll(tester).pixels + 1800);
        final anchor = browsing.visibleRow(tester);
        await browsing.screenshot(
          tester,
          reader.boundary,
          '${scene.$1}-browsed',
        );
        await browsing.close(tester);
        await browsing.open(tester);
        expect(browsing.visibleRow(tester).key, anchor.key);
        expect(row(body, 71).hitTestable(), findsNothing);
        await browsing.screenshot(
          tester,
          reader.boundary,
          '${scene.$1}-restored',
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(scene.$2),
    );
  }
}
