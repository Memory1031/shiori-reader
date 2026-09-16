import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

void main() {
  final key = LocalBookIdentity.book('a' * 64);
  LocalBookContent parse(String body, {String css = ''}) {
    final files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><style>$css</style></head><body>$body</body></html>',
    );
    return EpubParser(zipFiles(files), key, 'inline.epub').parse().content;
  }

  const src = '../images/%E6%98%9F%20%E7%A9%BA.png';
  test(
    'em image remains in prose with rune offsets, links and JSON round trip',
    () {
      final content = parse(
        '''<p id="one"> 😀守护星<img class="symbol" src="$src"/>（火星）<a href="#one">返回</a><img style="width:.5em" src="$src"/>。</p>''',
        css: 'img.symbol {height:1em}',
      );
      final chapter = content.chapters.first;
      expect(chapter.blocks, hasLength(1));
      final block = chapter.blocks.single as ParagraphBlock;
      expect(block.text, '😀守护星\uFFFC（火星）返回\uFFFC。');
      expect(block.inlineImages.map((i) => i.offset), [4, 11]);
      expect(block.inlineImages.first.heightEm, 1);
      expect(block.inlineImages.last.widthEm, .5);
      expect(content.links.single.sourceOffset, 9);
      expect(ContentBlock.fromJson(block.toJson()), block);
      expect(chapter.blocks.expand((b) => b.mediaRefs), hasLength(2));
    },
  );
  test(
    'ordinary, block and oversized images remain independent illustrations',
    () {
      for (final style in [
        '',
        'display:block;height:1em',
        'height:10em',
        'width:80%',
      ]) {
        final chapter = parse(
          '<p>前<img style="$style" src="$src"/>后</p>',
        ).chapters.first;
        expect(chapter.blocks.whereType<ImageBlock>(), hasLength(1));
        expect(chapter.blocks.expand((b) => b.inlineImages), isEmpty);
      }
    },
  );
  test(
    'inline images survive heading normalization and duplicate occurrences',
    () {
      final chapter = parse(
        '<h4>标题<img style="height:1em" src="$src"/></h4><p>正文</p><p>同<img style="height:1em" src="$src"/></p><p>同<img style="height:1em" src="$src"/></p>',
      ).chapters.first;
      expect(chapter.blocks.first.inlineImages, hasLength(1));
      expect(chapter.blocks[2].blockKey, isNot(chapter.blocks[3].blockKey));
      for (final block in chapter.blocks) {
        expect(ContentBlock.fromJson(block.toJson()), block);
      }
    },
  );
  test('invalid offsets and foreign image ownership are rejected', () {
    final image = InlineImage(
      offset: 0,
      media: MediaRef(sourceId: key.sourceId, mediaId: 'x'),
      widthEm: 1,
      heightEm: 1,
    );
    expect(
      () => ParagraphBlock(text: 'text', inlineImages: [image]),
      throwsArgumentError,
    );
    expect(
      () => ParagraphBlock(text: '\uFFFC', inlineImages: [image, image]),
      throwsArgumentError,
    );
  });
}
