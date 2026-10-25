import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/txt/txt_parser.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/domain/contracts/local_search.dart';
import 'package:shiori/domain/bookmark_position.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_search_highlight.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';

ChapterContent txt(String source) {
  final original = parseTxt(
    utf8.encode(source),
    LocalBookIdentity.book('b' * 64),
    'sample.txt',
    TxtEncoding.utf8,
  ).chapters.single;
  return ChapterContent(
    key: original.key,
    title: original.title,
    blocks: original.blocks,
    lineSeparated: true,
  );
}

const style = TextStyle(
  inherit: false,
  fontFamily: 'Ahem',
  fontSize: 20,
  height: 1.6,
  color: Colors.black,
);

PageLayout layout(
  ChapterContent content, {
  double width = 300,
  double height = 1000,
  int columns = 1,
  int chunkSize = 800,
  double spacing = 20,
  double scale = 1,
  TxtBlankLineMode mode = TxtBlankLineMode.merge,
}) => PageLayout(
  index: ChunkIndex(content, maxCodePoints: chunkSize),
  width: width,
  height: height,
  columns: columns,
  style: style,
  scaler: TextScaler.linear(scale),
  direction: TextDirection.ltr,
  paragraphSpacing: spacing,
  txtBlankLines: mode,
);

List<ReaderPage> pages(PageLayout layout) {
  final result = <ReaderPage>[];
  var cursor = const PageCursor(0, 0);
  while (true) {
    final page = layout.forward(cursor);
    if (page == null) return result;
    expect(result.length, lessThan(1000));
    expect((
      page.end.unit,
      page.end.offset,
    ), isNot((cursor.unit, cursor.offset)));
    result.add(page);
    cursor = page.end;
  }
}

String visible(WidgetTester tester) => tester
    .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
    .map((w) => w.text)
    .join('|');

String painted(ReaderPage page) => page.fragments
    .where((f) => f.text?.isNotEmpty == true)
    .map((f) => f.text)
    .join('|');

void main() {
  test(
    'TXT layout metadata round trips without changing text or identities',
    () {
      final content = txt('第一章\r\n　甲😀\r\n\r\n乙');
      final legacy = ChapterContent(
        key: content.key,
        title: content.title,
        blocks: content.blocks,
      );
      expect(content.lineSeparated, isTrue);
      expect(content.blocks, legacy.blocks);
      expect(content.contentRevision, legacy.contentRevision);
      expect(content, isNot(legacy));
      expect(ChapterContent.fromJson(content.toJson()), content);
      expect(ChapterContent.fromJson(legacy.toJson()).lineSeparated, isFalse);
      expect(
        content.blocks
            .map((b) => b is ParagraphBlock ? b.text : (b as HeadingBlock).text)
            .join(),
        '第一章\n　甲😀\n\n乙',
      );
    },
  );

  testWidgets(
    'blank runs follow merge or max rules using measured line height',
    (tester) async {
      for (final newline in ['\n', '\r\n', '\r']) {
        for (final scale in [1.0, 1.5]) {
          final painter = TextPainter(
            text: const TextSpan(text: ' ', style: style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
          )..layout();
          final row = painter.height;
          painter.dispose();
          for (final count in [0, 1, 2, 3]) {
            final content = txt(
              ['甲', ...List.filled(count, '　\t'), '乙'].join(newline),
            );
            for (final mode in TxtBlankLineMode.values) {
              final page = pages(
                layout(content, scale: scale, mode: mode),
              ).single;
              final gap =
                  page.fragments.fold(0.0, (sum, f) => sum + f.height) -
                  row * 2;
              final expected =
                  mode == TxtBlankLineMode.merge || count * row < 20
                  ? 20.0
                  : count * row;
              expect(gap, closeTo(expected, .01));
              expect(
                page.fragments
                    .where((f) => f.text!.isNotEmpty)
                    .map((f) => f.text),
                ['甲', '乙'],
              );
            }
          }
        }
      }
      final longBlank = txt('甲\n${' ' * 1000}\n乙');
      expect(ChunkIndex(longBlank, maxCodePoints: 16).chunks, hasLength(3));
      expect(pages(layout(longBlank)).single.fragments, hasLength(2));
    },
  );

  testWidgets('structural endings do not create extra rows or terminal pages', (
    tester,
  ) async {
    for (final text in ['甲\n乙\n', '甲\n乙']) {
      final content = txt(text);
      final result = pages(layout(content, height: 84));
      expect(result, hasLength(1));
      expect(result.single.fragments.map((f) => f.height), [32.0, 52.0]);
    }
    final separator = layout(txt('甲\n乙')).forward(const PageCursor(0, 1))!;
    expect(separator.fragments.single.text, '乙');
    expect(separator.fragments.single.height, 32);
    expect(layout(txt('甲\n')).forward(const PageCursor(0, 1)), isNull);
    final heading = txt('第一章\n正文');
    final clean = ChapterContent(
      key: heading.key,
      title: heading.title,
      blocks: [
        HeadingBlock(text: '第一章'),
        ParagraphBlock(text: '正文'),
      ],
      lineSeparated: true,
    );
    expect(
      pages(layout(heading)).single.fragments.map((f) => f.height),
      pages(layout(clean)).single.fragments.map((f) => f.height),
    );
    for (final length in [799, 800, 801]) {
      final content = txt('${'甲' * length}\n');
      final index = ChunkIndex(content);
      expect(index.chunks.last.text, isNot('\n'));
      final result = pages(layout(content, height: 160, spacing: 0));
      expect(
        result.expand((p) => p.fragments).map((f) => f.text).join(),
        '甲' * length,
      );
      expect(
        result.every((p) => p.fragments.any((f) => f.text!.isNotEmpty)),
        isTrue,
      );
      final last = result.last.fragments.last;
      expect(index.chunks[last.unit].start + last.end, length + 1);
    }
  });

  testWidgets('heading gaps and small measured rows use max rather than sum', (
    tester,
  ) async {
    for (final count in [0, 1, 2]) {
      final heading = txt('第一章\n${'\n' * count}正文');
      for (final mode in TxtBlankLineMode.values) {
        final page = pages(layout(heading, mode: mode)).single;
        final title = page.fragments.first;
        final body = page.fragments.last;
        final between =
            page.fragments.skip(1).fold(0.0, (sum, f) => sum + f.height) - 32;
        expect(title.spacingBefore, 42);
        expect(body.text, '正文');
        expect(
          between,
          mode == TxtBlankLineMode.preserve && count == 2 ? 64 : 52,
        );
      }
    }
    final page = pages(
      layout(
        txt('甲\n\n乙'),
        spacing: 32,
        scale: .5,
        mode: TxtBlankLineMode.preserve,
      ),
    ).single;
    expect(page.fragments.fold(0.0, (sum, f) => sum + f.height) - 32, 32);
  });

  testWidgets('preserved leading blanks do not orphan a TXT heading', (
    tester,
  ) async {
    final content = txt('${'\n' * 4}第一章\n${'甲' * 16}');
    final result = pages(
      layout(content, width: 160, height: 200, mode: TxtBlankLineMode.preserve),
    );
    expect(result, hasLength(2));
    expect(result.first.fragments.every((f) => f.text == ''), isTrue);
    expect(result.first.end.unit, 4);
    expect(result.last.fragments.map((f) => f.text), ['第一章', '甲' * 16]);
  });

  testWidgets(
    'TXT mode keeps bookmark anchors and search glyph source offsets',
    (tester) async {
      final content = txt('head\n\n　\t😀prefix MARK suffix\n');
      final source = (content.blocks[2] as ParagraphBlock).text;
      final start = source.substring(0, source.indexOf('MARK')).runes.length;
      final position = ChunkIndex(
        content,
      ).position(2, start / source.runes.length);
      final legacy = ChapterContent(
        key: content.key,
        title: content.title,
        blocks: content.blocks,
      );
      final bookmark = BookmarkPositionIndex([
        legacy,
      ]).capture(content.key, position)!;
      final active = ValueNotifier<LocalSearchBodyHit?>(
        LocalSearchBodyHit(
          snapshot: LocalSearchSnapshotId('txt-source'),
          chapter: content.key,
          contentRevision: content.contentRevision,
          blockKey: content.blocks[2].blockKey,
          blockIndex: 2,
          start: start,
          end: start + 4,
          snippet: const LocalSearchSnippet(
            before: '',
            match: 'MARK',
            after: '',
          ),
        ),
      );
      addTearDown(active.dispose);
      final controller = PagedReaderController();
      List<Rect>? previous;
      for (final mode in TxtBlankLineMode.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 220,
                child: ReaderSearchHighlightScope(
                  active: active,
                  content: content,
                  child: PagedReaderViewport(
                    content: content,
                    controller: controller,
                    initialPosition: position,
                    textStyle: style,
                    paragraphSpacing: 20,
                    txtBlankLines: mode,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boxes = tester
            .renderObjectList<ReaderSearchTextRender>(
              find.byType(ReaderPaintedSearchText),
            )
            .expand((r) => r.selectedBoxes)
            .toList();
        expect(boxes, isNotEmpty);
        expect(
          boxes.fold(0.0, (sum, box) => sum + box.width),
          closeTo(80, .01),
        );
        if (previous != null) {
          expect(
            boxes.map((r) => (r.left, r.width)),
            previous.map((r) => (r.left, r.width)),
          );
        }
        previous = boxes;
        expect(controller.capture(), position);
        expect(
          BookmarkPositionIndex([
            content,
          ]).resolve(content.key, bookmark).anchor!.position,
          bookmark.position,
        );
      }
    },
  );

  testWidgets(
    'page edges consume gaps once and large blank runs make progress',
    (tester) async {
      final separated = txt('甲\n\n乙\n\n丙\n');
      for (final mode in TxtBlankLineMode.values) {
        final result = pages(layout(separated, height: 64, mode: mode));
        expect(result.map(painted).where((text) => text.isNotEmpty), [
          '甲',
          '乙',
          '丙',
        ]);
        for (final page in result) {
          final text = page.fragments.where((f) => f.text!.isNotEmpty);
          if (text.isNotEmpty) expect(text.first.spacingBefore, 0);
        }
        expect(result.last.end.unit, ChunkIndex(separated).chunks.length);
      }
      final huge = txt('甲\n${'\n' * 10000}乙');
      final merge = layout(huge);
      expect(pages(merge), hasLength(1));
      expect(merge.measuredChunks, 2);
      final authored = layout(
        txt('甲\n${'\n' * 250}乙'),
        height: 64,
        mode: TxtBlankLineMode.preserve,
      );
      final result = pages(authored);
      final blanks = result
          .expand((p) => p.fragments)
          .where((f) => f.text == '');
      expect(blanks.fold(0.0, (height, f) => height + f.height), 250 * 32);
      expect(authored.measuredChunks, lessThan(10));
      final leading = pages(
        layout(txt('甲\n\n\n乙'), height: 64, mode: TxtBlankLineMode.preserve),
      );
      expect(leading[1].start.unit, 2);
      expect(leading[1].visibleStart.unit, 3);
    },
  );

  testWidgets('TXT policy leaves EPUB explicit breaks and gaps untouched', (
    tester,
  ) async {
    final source = txt('甲\n\n　\t乙\n');
    final epub = ChapterContent(
      key: source.key,
      title: source.title,
      blocks: source.blocks,
    );
    final merge = pages(layout(epub));
    final preserve = pages(layout(epub, mode: TxtBlankLineMode.preserve));
    expect(merge.map(painted), preserve.map(painted));
    expect(
      merge.single.fragments.map((f) => f.height),
      preserve.single.fragments.map((f) => f.height),
    );
    expect(merge.single.fragments.first.text, endsWith('\n'));
  });

  for (final (columns, initialMode) in [
    for (final columns in [1, 2])
      for (final mode in TxtBlankLineMode.values) (columns, mode),
  ]) {
    testWidgets(
      '$columns columns/${initialMode.name} preserve source coverage and reverse slices',
      (tester) async {
        final content = txt('　${'甲😀é乙。' * 90}\n\n${'丙丁' * 50}\n');
        final engine = layout(
          content,
          width: 160,
          height: 180,
          columns: columns,
          chunkSize: 32,
          mode: initialMode,
        );
        final result = pages(engine);
        expect(result.length, greaterThan(2));
        final fragments = result.expand((p) => p.fragments).toList();
        for (var unit = 0; unit < engine.index.chunks.length; unit++) {
          if (engine.index.chunks[unit].text!.trim().isEmpty) continue;
          final slices = fragments.where((f) => f.unit == unit).toList();
          expect(slices.first.start, 0);
          expect(slices.last.end, engine.index.chunks[unit].text!.runes.length);
          for (var i = 1; i < slices.length; i++) {
            expect(slices[i].start, slices[i - 1].end);
          }
        }
        expect(
          fragments.map((f) => f.text).join(),
          content.blocks
              .cast<ParagraphBlock>()
              .map((b) => b.text.replaceAll('\n', ''))
              .join(),
        );
        final backward = engine.backward(result.last.end)!;
        expect(backward.fragments.last.end, result.last.fragments.last.end);
        expect(backward.fragments.last.text, isNot(contains('\n')));
      },
    );

    testWidgets(
      '$columns columns/${initialMode.name} restore cold anchors and repeat canonical pages',
      (tester) async {
        final content = txt(
          List.generate(45, (i) => '第$i段${'甲乙' * (i % 4 + 1)}。\n\n').join(),
        );
        final engine = layout(
          content,
          width: 300,
          height: 240,
          columns: columns,
          mode: initialMode,
        );
        final canonical = pages(engine);
        final pivot = canonical[canonical.length ~/ 2];
        final target = pivot.fragments.firstWhere((f) => f.text!.isNotEmpty);
        final chunk = engine.index.chunks[target.unit];
        final initial = engine.index.position(
          target.unit,
          (chunk.start + target.start) / chunk.total,
        );
        final controller = PagedReaderController();
        Future<void> mount(
          double width, {
          TxtBlankLineMode? mode,
          double fontSize = 20,
          double lineHeight = 1.6,
        }) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: width,
                  height: 240,
                  child: PagedReaderViewport(
                    content: content,
                    controller: controller,
                    initialPosition: initial,
                    textStyle: style.copyWith(
                      fontSize: fontSize,
                      height: lineHeight,
                    ),
                    paragraphSpacing: 20,
                    txtBlankLines: mode ?? initialMode,
                    columns: columns,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> turn(bool next) async {
          final future = next ? controller.next() : controller.previous();
          await tester.pumpAndSettle();
          await future;
        }

        await mount(columns * 300 + (columns - 1) * 72.0);
        expect(visible(tester), painted(pivot));
        final anchor = controller.capture();
        await mount(
          columns * 300 + (columns - 1) * 72.0,
          mode: initialMode == TxtBlankLineMode.merge
              ? TxtBlankLineMode.preserve
              : TxtBlankLineMode.merge,
          fontSize: 24,
          lineHeight: 1.8,
        );
        expect(controller.capture(), anchor);
        await mount(columns * 300 + (columns - 1) * 72.0);
        expect(controller.capture(), anchor);
        expect(visible(tester), painted(pivot));
        await turn(true);
        await turn(false);
        expect(visible(tester), painted(pivot));
        await mount(columns * 260 + (columns - 1) * 72.0);
        expect(tester.takeException(), isNull);
        await mount(columns * 300 + (columns - 1) * 72.0);
        expect(visible(tester), painted(pivot));
      },
    );
  }

  testWidgets('render representative TXT single and double pages', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final output = Platform.environment['SHIORI_TXT_SCREENSHOTS'];
    final font = Platform.environment['SHIORI_TXT_FONT'];
    if (font != null) {
      await tester.runAsync(() async {
        final bytes = await File(font).readAsBytes();
        await (FontLoader(
          'TxtPreview',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
    }
    final content = txt(
      List.generate(
        18,
        (i) =>
            '　　${['午后的图书馆很安静，窗外的树影轻轻摇动。', '她翻开书页，记下刚刚想到的问题。', '走廊传来脚步声，随后又恢复了安静。'][i % 3]}\n${i % 5 == 4 ? '\n\n' : '\n'}',
      ).join(),
    );
    final boundary = GlobalKey();
    for (final mode in TxtBlankLineMode.values) {
      for (final size in [const Size(390, 760), const Size(1400, 880)]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        final columns = size.width > 1000 ? 2 : 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(scaffoldBackgroundColor: const Color(0xfff3ead5)),
            home: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: const Color(0xfff3ead5),
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: PagedReaderViewport(
                    key: ValueKey((size, mode)),
                    content: content,
                    controller: PagedReaderController(),
                    textStyle: style.copyWith(
                      fontFamily: font == null ? 'Ahem' : 'TxtPreview',
                      fontSize: columns == 2 ? 28 : 20,
                    ),
                    paragraphSpacing: 20,
                    columns: columns,
                    txtBlankLines: mode,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
              .first
              .text,
          (content.blocks.first as ParagraphBlock).text.replaceAll('\n', ''),
        );
        expect(
          tester
              .widgetList<ReaderLinkedText>(find.byType(ReaderLinkedText))
              .every((w) => !w.text.contains('\n')),
          isTrue,
        );
        if (output != null) {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File(
              '$output/txt-${mode.name}-$columns.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    }
  });
}
