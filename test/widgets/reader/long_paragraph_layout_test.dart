import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/viewport/page_layout.dart';
import 'package:shiori/features/reader/viewport/render_chunk.dart';
import '../../data/local/epub_prose_semantics_test.dart' show paragraphs;
import 'page_boundaries_test.dart' show chapter;

void main() {
  testWidgets(
    'long source lengths preserve chunk/page coverage and only final bottom edges',
    (tester) async {
      final text = '正文😀é文字。' * 1600;
      for (final authored in [
        '<p style="border:1px solid black;padding:4px">$text</p>',
        '<p style="text-indent:-2em;padding-left:2em;border:1px solid black;padding-bottom:7px">$text</p>',
        '<p style="text-indent:2em;clear:both">$text<span style="float:right;text-indent:0">尾注</span></p>',
      ]) {
        final block = paragraphs(authored).single;
        final content = ChapterContent(
          key: chapter(false).key,
          title: 'Long',
          blocks: [block],
        );
        final index = ChunkIndex(content);
        expect(index.chunks.length, greaterThan(10));
        expect(
          index.chunks.every((c) => c.total == block.text.runes.length),
          isTrue,
        );
        final layout = PageLayout(
          index: index,
          width: 300,
          height: 200,
          style: const TextStyle(fontSize: 20, height: 1.5),
          scaler: TextScaler.noScaling,
          direction: TextDirection.ltr,
        );
        final fragments = <PageFragment>[];
        var cursor = const PageCursor(0, 0), pages = 0;
        while (true) {
          final page = layout.forward(cursor);
          if (page == null) break;
          expect(++pages, lessThan(2000));
          fragments.addAll(page.fragments);
          cursor = page.end;
        }
        expect(fragments.map((f) => f.text).join(), block.text);
        expect(
          fragments.take(fragments.length - 1).every((f) => f.boxBottom == 0),
          isTrue,
        );
        if (block.box != null || block.layout != null) {
          expect(fragments.last.boxBottom, greaterThan(0));
        }
        final backwards = layout.backward(cursor)!;
        expect(backwards.fragments.last.text, fragments.last.text);
      }
    },
  );
}
