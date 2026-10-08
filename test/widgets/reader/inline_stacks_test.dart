import 'dart:convert';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/features/reader/reader_inline_stack.dart';
import 'package:shiori/features/reader/reader_preferences.dart';
import 'package:shiori/features/reader/reader_inline_images.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/block_style.dart';
import 'package:shiori/features/reader/viewport/paragraph_flow.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/viewport/page_boundaries.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import '../../data/local/epub_inline_stacks_test.dart'
    show stackedChapter, stackStyle;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import '../../data/local/epub_structure_test.dart' show parse;
import '../../data/local/support/epub_fixtures.dart';

void main() {
  testWidgets('two-line inline text keeps surrounding prose on one baseline', (
    tester,
  ) async {
    final files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode(
      '''<html><body><p>前文「<span style="display:inline-block;text-align:center;text-indent:0;line-height:1em"><span style="font-size:.68em">SAMPLE</span><br/>示例</span>」后文。</p></body></html>''',
    );
    final content = parse(files).content.chapters.first;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SizedBox(
          width: 390,
          height: 800,
          child: ReaderContentView(content: content),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byType(ReaderLinkedText),
            matching: find.byType(RichText),
          )
          .first,
    );
    final plain = paragraph.text.toPlainText();
    Rect box(String word) {
      final start = plain.indexOf(word);
      return paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + word.length),
          )
          .first
          .toRect();
    }

    expect(
      box('前文').top,
      closeTo(box('后文').top, .05),
      reason: 'the internal br must not break the surrounding paragraph',
    );
    expect(find.byType(ReaderInlineStack), findsOneWidget);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      final label = tester
          .getSemantics(find.byType(ReaderInlineStack))
          .getSemanticsData()
          .label;
      expect(label, contains('SAMPLE\n示例'));
      expect(label.replaceAll('\n', ''), '前文「SAMPLE示例」后文。');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'actual rows center, preserve authored font sizes, baseline and nonlinear scaling',
    (tester) async {
      final c = stackedChapter(
        '<p>前「<span style="$stackStyle"><span style="font-size:.68em">SAMPLE</span><br/>示例</span>」后</p>',
      );
      final b = c.blocks.single as ParagraphBlock;
      for (final localHeight in ['2', '2em']) {
        final authored =
            stackedChapter(
                  '<p><span style="$stackStyle"><span style="font-size:.68em;line-height:$localHeight">SAMPLE</span><br/>示例</span></p>',
                ).blocks.single
                as ParagraphBlock;
        final local = readerStackLayout(
          text: authored.text,
          stack: authored.inlineStacks.single,
          styles: authored.inlineStyles,
          style: const TextStyle(fontSize: 20),
          scaler: const StackScaler(),
          direction: TextDirection.ltr,
        );
        final reference = TextPainter(
          text: TextSpan(
            text: 'SAMPLE',
            style: TextStyle(
              fontSize: const StackScaler().scale(13.6),
              height: 2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(
          ((local.upper as TextSpan).children!.first as TextSpan).style!.height,
          closeTo(2, .001),
        );
        // Use the engine's shaped line box, including its pixel rounding.
        expect(local.geometry.upper.height, closeTo(reference.height, .01));
        reference.dispose();
      }
      for (final scaler in [TextScaler.noScaling, const StackScaler()]) {
        final l = readerStackLayout(
          text: 'SAMPLE\n示例',
          stack: b.inlineStacks.single,
          styles: b.inlineStyles,
          style: const TextStyle(fontSize: 20, height: 1.6),
          scaler: scaler,
          direction: TextDirection.ltr,
        );
        final a = (l.upper as TextSpan).children!.first as TextSpan;
        expect(a.style!.fontSize, closeTo(scaler.scale(13.6), .001));
        expect(
          l.geometry.upper.center.dx,
          closeTo(l.geometry.lower.center.dx, .001),
        );
        expect(l.geometry.upper.bottom, closeTo(l.geometry.lower.top, .001));
        expect(l.geometry.upper.height, closeTo(scaler.scale(20), .01));
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 360,
                child: ReaderLinkedText(
                  text: b.text,
                  prefix: '',
                  blockOffset: 0,
                  links: const [],
                  inlineStacks: b.inlineStacks,
                  inlineStyles: b.inlineStyles,
                  style: const TextStyle(fontSize: 20, height: 1.6),
                  align: TextAlign.start,
                  scaler: scaler,
                ),
              ),
            ),
          ),
        );
        final stack = find.byType(ReaderInlineStack);
        expect(stack, findsOneWidget);
        final w = tester.widget<ReaderInlineStack>(stack);
        expect(tester.getRect(stack).size, w.layout.geometry.size);
        final p = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(ReaderLinkedText),
            matching: find.byType(RichText),
          ),
        );
        final plain = p.text.toPlainText();
        final after = p
            .getBoxesForSelection(
              TextSelection(
                baseOffset: plain.indexOf('」'),
                extentOffset: plain.indexOf('」') + 1,
              ),
            )
            .single;
        final box = tester.renderObject<RenderBox>(stack);
        final glyph = TextPainter(
          text: TextSpan(
            text: '」',
            style: const TextStyle(fontSize: 20, height: 1.6),
          ),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final baseline = glyph.computeDistanceToActualBaseline(
          TextBaseline.alphabetic,
        );
        // Selection boxes include the full line-height around the adjacent glyph.
        expect(
          box
              .localToGlobal(
                Offset(0, w.layout.geometry.baseline / w.factor),
                ancestor: p,
              )
              .dy,
          closeTo(
            after.top +
                baseline -
                glyph
                    .getBoxesForSelection(
                      const TextSelection(baseOffset: 0, extentOffset: 1),
                    )
                    .single
                    .top,
            .05,
          ),
        );
        glyph.dispose();
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final columns in [1, 2]) {
    testWidgets(
      'stack boundaries, mixed atoms, canonical reverse pages and restore in $columns columns',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(columns == 1 ? 600 : 1400, 700);
        addTearDown(tester.view.reset);
        final prefix = '前文😀。' * 11;
        final body = '$prefix上层字母\n下层中文末文漢字\uFFFC${'后续正文。' * 55}';
        final start = prefix.runes.length;
        final stack = InlineStack(
          start: start,
          length: 9,
          separator: start + 4,
          upperLineHeightEm: 1,
          lowerLineHeightEm: 1,
        );
        final b = ParagraphBlock(
          text: body,
          inlineStacks: [stack],
          inlineRuby: [
            InlineRuby(start: start + 11, length: 2, annotation: 'かんじ'),
          ],
          inlineImages: [
            InlineImage(
              offset: start + 13,
              media: fixtureMediaRef(0),
              widthEm: 1,
              heightEm: 1,
            ),
          ],
        );
        final c = ChapterContent(
          key: fixtureChapterKey(FixtureScenario.shortChapter),
          title: 'Stack',
          blocks: [b],
        );
        final index = ChunkIndex(c, maxCodePoints: start + 2);
        expect(
          index.chunks.any(
            (chunk) => stack.start < chunk.end && chunk.end < stack.end,
          ),
          isFalse,
        );
        final layout = PageLayout(
          index: index,
          width: 240,
          height: 170,
          columns: columns,
          style: const TextStyle(fontSize: 20, height: 1.6),
          scaler: TextScaler.noScaling,
          direction: TextDirection.ltr,
        );
        final bounds = PageBoundaries(layout);
        final pages = <ReaderPage>[];
        var cursor = const PageCursor(0, 0);
        while (true) {
          final p = bounds.forward(cursor);
          if (p == null) break;
          expect(PageBoundaries.compare(p.end, cursor), greaterThan(0));
          pages.add(p);
          expect(pages.length, lessThan(50));
          cursor = p.end;
          for (final f in p.fragments) {
            final end = index.chunks[f.unit].start + f.end;
            expect(stack.start < end && end < stack.end, isFalse);
          }
        }
        expect(pages.length, greaterThan(2));
        expect(
          pages.expand((p) => p.fragments).map((f) => f.text ?? '').join(),
          body,
        );
        for (final original in pages.reversed) {
          final p = bounds.backward(cursor)!;
          expect(PageBoundaries.compare(p.start, original.start), 0);
          cursor = p.start;
        }
        // This mapping crosses image, Ruby and stack in the same original text.
        final spans = readerInlineSpans(
          text: body,
          offset: 0,
          images: b.inlineImages,
          ruby: b.inlineRuby,
          stacks: [stack],
          style: const TextStyle(fontSize: 20),
          maxWidth: 240,
        );
        final displayed = TextSpan(children: spans).toPlainText();
        expect(
          readerInlineSourceBoundary(
            body,
            0,
            b.inlineRuby,
            displayed.length,
            stacks: [stack],
          ),
          body.length,
        );
        final controller = PagedReaderController();
        final preferences = ReaderPreferences(null);
        addTearDown(preferences.dispose);
        Future<void> show(double width, double font) async {
          preferences.update(preferences.value.copyWith(fontSize: font));
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Center(
                child: SizedBox(
                  width: width,
                  height: 500,
                  child: ReaderContentView(
                    content: c,
                    viewportController: controller,
                    preferences: preferences,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await show(columns == 1 ? 390 : 1200, 20);
        expect(
          tester
              .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
              .columns,
          columns,
        );
        final state = tester.state(find.byType(PagedReaderViewport));
        for (final at in [stack.start + 1, stack.separator, stack.end - 1]) {
          final position = ReaderPosition(
            contentRevision: c.contentRevision,
            blockKey: b.blockKey,
            blockIndex: 0,
            blockFraction: at / body.runes.length,
            chapterFraction: at / body.runes.length,
          );
          controller.restore(position);
          await tester.pumpAndSettle();
          expect(find.byType(ReaderInlineStack), findsOneWidget);
          expect(
            controller.capture()!.blockFraction,
            closeTo(position.blockFraction, 1e-8),
          );
          expect(controller.usedFallback, isFalse);
          await show(columns == 1 ? 340 : 1150, 24);
          expect(tester.state(find.byType(PagedReaderViewport)), same(state));
          expect(find.byType(ReaderInlineStack), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'hanging flow keeps two rows atomic and following links clickable',
    (tester) async {
      final prefix = '前链${'前文。' * 5}';
      final text = '${prefix}SAMPLE\n示例后链1${'后文。' * 20}';
      final start = prefix.runes.length;
      final stack = InlineStack(start: start, length: 9, separator: start + 6);
      final b = ParagraphBlock(
        text: text,
        hangingIndentEm: 2,
        inlineStacks: [stack],
      );
      final c = ChapterContent(
        key: fixtureChapterKey(FixtureScenario.shortChapter),
        title: 'Flow',
        blocks: [b],
      );
      final flow = readerParagraphFlow(
        block: b,
        stacks: [stack],
        text: text,
        offset: 0,
        width: 180,
        style: const TextStyle(fontSize: 20, height: 1.6),
        scaler: TextScaler.noScaling,
      );
      expect(flow.lines.length, greaterThan(3));
      expect(flow.end, text.runes.length);
      expect(
        flow.lines.any((l) => start < l.end && l.end < stack.end),
        isFalse,
      );
      final links = [
        LocalContentLink(
          source: c.key,
          sourceBlockKey: b.blockKey,
          label: '前链',
          sourceOffset: 0,
          sourceLength: 2,
          target: c.key,
          targetBlockKey: b.blockKey,
        ),
        LocalContentLink(
          source: c.key,
          sourceBlockKey: b.blockKey,
          label: '后链',
          sourceOffset: stack.end,
          sourceLength: 2,
          target: c.key,
          targetBlockKey: b.blockKey,
        ),
        LocalContentLink(
          source: c.key,
          sourceBlockKey: b.blockKey,
          label: '1',
          sourceOffset: stack.end + 2,
          target: c.key,
          targetBlockKey: b.blockKey,
          footnoteText: '合成注释',
        ),
      ];
      final activated = <LocalContentLink>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 500,
                child: PagedReaderViewport(
                  content: c,
                  controller: PagedReaderController(),
                  contentLinks: links,
                  onLink: activated.add,
                  onFootnote: activated.add,
                  textStyle: const TextStyle(fontSize: 20, height: 1.6),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReaderInlineStack), findsOneWidget);
      for (final label in ['前链', '后链', '1']) {
        final finder = find
            .descendant(
              of: find.byType(ReaderLinkedText),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is RichText &&
                    w.text
                        .toPlainText(includeSemanticsLabels: false)
                        .contains(label),
              ),
            )
            .last;
        final p = tester.renderObject<RenderParagraph>(finder);
        final at = p.text
            .toPlainText(includeSemanticsLabels: false)
            .indexOf(label);
        final box = p
            .getBoxesForSelection(
              TextSelection(baseOffset: at, extentOffset: at + label.length),
            )
            .single
            .toRect();
        await tester.tapAt(p.localToGlobal(box.center));
        await tester.pump();
      }
      expect(activated, links);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'layout-only changes invalidate the same viewport without changing semantic identity',
    (tester) async {
      final stacked = stackedChapter(
        '<p>前<span style="$stackStyle">SAMPLE<br/>示例</span>后</p>',
      );
      final plain = ChapterContent.fromJson(
        stacked.toJson()
          ..['blocks'] = [
            stacked.blocks.single.toJson()..remove('inlineStacks'),
          ],
      );
      expect(plain.contentRevision, stacked.contentRevision);
      expect(plain.blocks.single.blockKey, stacked.blocks.single.blockKey);
      final controller = PagedReaderController();
      Future<void> show(ChapterContent c) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PagedReaderViewport(content: c, controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(plain);
      final state = tester.state(find.byType(PagedReaderViewport));
      final generation = controller.layoutGeneration;
      expect(find.byType(ReaderInlineStack), findsNothing);
      await show(stacked);
      expect(tester.state(find.byType(PagedReaderViewport)), same(state));
      expect(controller.layoutGeneration, greaterThan(generation));
      expect(find.byType(ReaderInlineStack), findsOneWidget);
    },
  );
  testWidgets(
    'mixed stack baselines downgrade before pagination and keep the complete source',
    (tester) async {
      const a =
          '<span style="$stackStyle"><span style="line-height:6em">A</span><br/>a</span>';
      const b =
          '<span style="$stackStyle">B<br/><span style="line-height:6em">b</span></span>';
      const base = TextStyle(fontSize: 20, height: 1.2);
      for (final prefix in ['', '${'Before ' * 30}<br/>']) {
        for (final group in [
          (html: '$a$b', source: 'A\naB\nb', units: [a, b]),
          (
            html: '$a<span style="font-size:4em">Big</span>',
            source: 'A\naBig',
            units: [a],
          ),
        ]) {
          final c = stackedChapter(
            '<p>$prefix${group.html} After ${'tail ' * 80}</p>',
          );
          final block = c.blocks.single as ParagraphBlock;
          double probe(List<InlineStack> stacks, String text, int offset) {
            final p =
                TextPainter(
                    text: TextSpan(
                      style: base,
                      children: readerInlineSpans(
                        text: text,
                        offset: offset,
                        images: const [],
                        stacks: stacks,
                        styles: block.inlineStyles,
                        style: base,
                      ),
                    ),
                    textDirection: TextDirection.ltr,
                  )
                  ..setPlaceholderDimensions(
                    readerInlineDimensions(
                      offset: offset,
                      length: text.runes.length,
                      images: const [],
                      stacks: stacks,
                      text: text,
                      styles: block.inlineStyles,
                      style: base,
                      scaler: TextScaler.noScaling,
                      maxWidth: 700,
                    ),
                  )
                  ..layout(maxWidth: 700);
            try {
              return p.height;
            } finally {
              p.dispose();
            }
          }

          final stacks = block.inlineStacks;
          expect(stacks, hasLength(group.units.length));
          final separate = stacks
              .map(
                (s) => probe(
                  [s],
                  String.fromCharCodes(
                    block.text.runes.skip(s.start).take(s.length),
                  ),
                  s.start,
                ),
              )
              .reduce((a, b) => a > b ? a : b);
          final mixed = probe(stacks, group.source, stacks.first.start);
          expect(mixed, greaterThan(separate + 10));
          final pageHeight = (separate + mixed) / 2;
          PageLayout layout(ChapterContent content) => PageLayout(
            index: ChunkIndex(content),
            width: 700,
            height: pageHeight,
            style: base,
            scaler: TextScaler.noScaling,
            direction: TextDirection.ltr,
            paragraphSpacing: 0,
          );
          for (final unit in group.units) {
            final single = stackedChapter('<p>$unit After</p>');
            expect(
              layout(single).inlineStacks(single.blocks.single),
              hasLength(1),
              reason:
                  'each unit must fit alone; only their mixed baseline overflows',
            );
          }
          final hardBreaks = stackedChapter('<p>$a<br/>$b After</p>');
          expect(
            layout(hardBreaks).inlineStacks(hardBreaks.blocks.single),
            hasLength(2),
            reason: 'authored hard breaks cannot combine the two baselines',
          );
          final l = layout(c);
          final active = l.inlineStacks(block);
          final bounds = PageBoundaries(l);
          var cursor = const PageCursor(0, 0);
          final pages = <ReaderPage>[];
          while (true) {
            final page = bounds.forward(cursor);
            if (page == null) break;
            expect(PageBoundaries.compare(page.end, cursor), greaterThan(0));
            expect(pages.length, lessThan(30));
            pages.add(page);
            cursor = page.end;
          }
          expect(cursor.unit, l.index.chunks.length);
          expect(
            pages.expand((p) => p.fragments).map((f) => f.text ?? '').join(),
            block.text,
          );
          expect(
            active.length,
            lessThan(group.units.length),
            reason: 'the fresh-page mixed row must downgrade',
          );
          for (final original in pages.reversed) {
            final rebuilt = bounds.backward(cursor)!;
            expect(PageBoundaries.compare(rebuilt.start, original.start), 0);
            expect(PageBoundaries.compare(rebuilt.end, original.end), 0);
            expect(
              rebuilt.fragments.map((f) => f.text),
              original.fragments.map((f) => f.text),
            );
            cursor = rebuilt.start;
          }
          expect(l.inlineStacks(block), same(active));
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 700,
                  height: pageHeight,
                  child: PagedReaderViewport(
                    content: c,
                    controller: PagedReaderController(),
                    textStyle: base,
                    paragraphSpacing: 0,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(ReaderInlineStack), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
  testWidgets('heading stack line heights follow the declaration font context', (
    tester,
  ) async {
    for (final sample in [
      (heading: '', upper: '', height: '1em', font: 28.0, basis: 28.0),
      (heading: '', upper: '', height: '1', font: 28.0, basis: 28.0),
      (
        heading: '',
        upper: 'font-size:.68em',
        height: '1em',
        font: 19.04,
        basis: 28.0,
      ),
      (
        heading: '',
        upper: 'font-size:.68em',
        height: '1',
        font: 19.04,
        basis: 19.04,
      ),
      (
        heading: 'font-size:2em',
        upper: '',
        height: '1em',
        font: 40.0,
        basis: 40.0,
      ),
      (
        heading: '',
        upper: 'font-size:20px',
        height: '1em',
        font: 25.0,
        basis: 28.0,
      ),
      (
        heading: '',
        upper: 'font-size:20px',
        height: '1',
        font: 25.0,
        basis: 25.0,
      ),
      (heading: '', upper: '', height: '16px', font: 28.0, basis: 20.0),
    ]) {
      final c = stackedChapter(
        '<h1 style="${sample.heading}"><span style="$stackStyle;line-height:${sample.height}"><span style="${sample.upper}">上层</span><br/>下层</span></h1><p>后续正文。</p>',
      );
      final block = c.blocks.first;
      expect(block, isA<HeadingBlock>());
      expect(ContentBlock.fromJson(block.toJson()), block);
      for (final scaler in [TextScaler.noScaling, const StackScaler()]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: scaler),
              child: PagedReaderViewport(
                content: c,
                controller: PagedReaderController(),
                textStyle: const TextStyle(fontSize: 20, height: 1.6),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rendered = tester.widget<ReaderInlineStack>(
          find.byType(ReaderInlineStack),
        );
        final l = rendered.layout;
        final upper = (l.upper as TextSpan).children!.first as TextSpan;
        expect(upper.style!.fontSize, closeTo(scaler.scale(sample.font), .001));
        expect(
          upper.style!.height,
          closeTo(scaler.scale(sample.basis) / scaler.scale(sample.font), .001),
          reason: '${sample.heading} / ${sample.upper} / ${sample.height}',
        );
        final reference = TextPainter(
          text: TextSpan(
            text: '上层',
            style:
                readerBlockStyle(
                  block,
                  const TextStyle(fontSize: 20, height: 1.6),
                  chapter: c.key,
                ).copyWith(
                  fontSize: scaler.scale(sample.font),
                  height:
                      scaler.scale(sample.basis) / scaler.scale(sample.font),
                ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final lower = TextPainter(
          text: l.lower,
          textDirection: TextDirection.ltr,
        )..layout();
        try {
          expect(l.geometry.upper.height, closeTo(reference.height, .01));
          expect(
            l.geometry.size.height,
            closeTo(reference.height + lower.height, .01),
          );
          expect(
            l.geometry.baseline,
            closeTo(
              reference.height +
                  lower.computeDistanceToActualBaseline(
                    TextBaseline.alphabetic,
                  ),
              .01,
            ),
          );
        } finally {
          reference.dispose();
          lower.dispose();
        }
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets(
    'oversized units expand into readable source and reach the real chapter end',
    (tester) async {
      for (final dimensions in [(70.0, 120.0), (300.0, 45.0)]) {
        final text = '上' * 30 + '\n下层${'后文。' * 20}';
        final b = ParagraphBlock(
          text: text,
          inlineStacks: [
            InlineStack(
              start: 0,
              length: 33,
              separator: 30,
              upperLineHeightEm: 3,
              lowerLineHeightEm: 3,
            ),
          ],
        );
        final index = ChunkIndex(
          ChapterContent(
            key: fixtureChapterKey(FixtureScenario.shortChapter),
            title: 'Fallback',
            blocks: [b],
          ),
        );
        final l = PageLayout(
          index: index,
          width: dimensions.$1,
          height: dimensions.$2,
          style: const TextStyle(fontSize: 20, height: 1.2),
          scaler: TextScaler.noScaling,
          direction: TextDirection.ltr,
          paragraphSpacing: 0,
        );
        expect(l.inlineStacks(b), isEmpty);
        var cursor = const PageCursor(0, 0);
        final seen = StringBuffer();
        var pages = 0;
        while (true) {
          final page = l.forward(cursor);
          if (page == null) break;
          expect(++pages, lessThan(150));
          expect(PageBoundaries.compare(page.end, cursor), greaterThan(0));
          seen.write(page.fragments.map((f) => f.text ?? '').join());
          cursor = page.end;
        }
        expect(seen.toString(), text);
        expect(cursor.unit, index.chunks.length);
      }
    },
  );
}

class StackScaler extends TextScaler {
  const StackScaler();
  @override
  double scale(double fontSize) =>
      fontSize < 18 ? fontSize * 2 : fontSize * 1.5;
  @override
  double get textScaleFactor => 1.5;
}
