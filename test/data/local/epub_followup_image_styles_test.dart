import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_text_styles.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';
import 'support/oriented_jpeg.dart';

ParsedEpub parse(String body, {String css = '', int? orientation}) {
  final files = epubFiles();
  files['OPS/images/test.png'] = fixturePng(80, 200, 2);
  files['OPS/images/test.jpg'] = orientation == null
      ? plainOrientationJpeg()
      : jpegWithSegments([orientationSegment(orientation)]);
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html><head><style>$css</style></head><body>$body</body></html>',
  );
  return EpubParser(
    zipFiles(files),
    NovelKey(sourceId: SourceId('local'), novelId: 'image-followup'),
    'synthetic.epub',
  ).parse();
}

String svg({
  String file = 'test.png',
  int width = 80,
  int height = 200,
  String attributes = '',
  String extra = '',
}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" '
    'viewBox="0 0 $width $height" $attributes>'
    '<image width="$width" height="$height" href="../images/$file"/>$extra</svg>';

void main() {
  test(
    'SVG alignment uses oriented axes while media and identities stay raw',
    () {
      for (final orientation in [6, 8]) {
        final markup = svg(file: 'test.jpg', width: 200, height: 80);
        final normal = parse('<p>Before.</p>$markup', orientation: orientation);
        final explicit = parse(
          '<p>Before.</p><div style="text-align:left">$markup</div>',
          orientation: orientation,
        );
        final a = normal.content.chapters.first;
        final image = a.blocks.whereType<ImageBlock>().single;
        expect(image.sizing!.alignment, ParagraphAlignment.center);
        expect(image.sizing!.role, ImageRole.flow);
        expect((image.width, image.height), (80, 200));
        expect(
          a.contentRevision,
          explicit.content.chapters.first.contentRevision,
        );
        expect(
          explicit.content.chapters.first.blocks
              .whereType<ImageBlock>()
              .single
              .sizing!
              .alignment,
          ParagraphAlignment.start,
        );
        expect(
          normal.media[image.media.mediaId.split('/').last],
          jpegWithSegments([orientationSegment(orientation)]),
        );
        final wrong = parse(
          '<p>Before.</p>${svg(file: 'test.jpg')}',
          orientation: orientation,
        ).content.chapters.first.blocks.whereType<ImageBlock>().single;
        expect(wrong.sizing!.alignment, isNull);
      }
    },
  );
  test('single-raster SVG containers retain edges without double padding', () {
    final a = parse(
      '<figure>${svg()}</figure><figure>${svg()}</figure>',
      css: 'figure {margin-bottom:1em;padding:0}',
    ).content.chapters.first;
    final images = a.blocks.whereType<ImageBlock>().toList();
    expect(images, hasLength(2));
    for (final image in images) {
      expect(image.box!.margins!.bottom, LayoutLength(1, LayoutUnit.em));
      expect(image.sizing!.alignment, ParagraphAlignment.center);
    }
    expect(images[0].box!.group, isNot(images[1].box!.group));
    final plain = parse(
      '<figure><img src="../images/test.png"/></figure>'
      '<figure><img src="../images/test.png"/></figure>',
      css: 'figure {margin-bottom:1em;padding:0;text-align:center}',
    ).content.chapters.first;
    expect(a.contentRevision, plain.contentRevision);
    for (var i = 0; i < images.length; i++) {
      expect(
        images[i].box!.margins,
        plain.blocks.whereType<ImageBlock>().elementAt(i).box!.margins,
      );
    }
    for (final complex in [
      svg(attributes: 'transform="scale(2)"'),
      svg(extra: '<path d="M0 0L1 1"/>'),
      '${svg()}${svg()}',
    ]) {
      final c = parse(
        '<figure>$complex</figure>',
        css: 'figure {margin-bottom:1em}',
      ).content.chapters.first;
      expect(
        c.blocks.whereType<ImageBlock>().every((b) => b.box == null),
        true,
      );
    }
  });
  test('image-free background shorthand restores existing panel metadata', () {
    const body = '<div class="panel"><h1>Title</h1><p>Body.</p></div>';
    const style = '.panel {padding:3px;border-radius:10px;margin-top:.5em;';
    final shorthand = parse(
      body,
      css: '$style background:none repeat scroll 0 0 #eee;}',
    ).content.chapters.first;
    final longhand = parse(
      body,
      css: '$style background-color:#eee;}',
    ).content.chapters.first;
    expect(shorthand.contentRevision, longhand.contentRevision);
    expect(
      shorthand.blocks.map((b) => b.box).toList(),
      longhand.blocks.map((b) => b.box).toList(),
    );
    final panel = shorthand.blocks.first.box!;
    expect(panel.backgroundColor, 0xffeeeeee);
    expect(panel.radius, LayoutLength(10));
    expect(panel.paddingEdges!.top, LayoutLength(3));
  });
  test(
    'background resets, longhand order and important remain authoritative',
    () {
      Map<String, String> styles(String declaration) {
        final doc = html.parse('<html><body><div>Body.</div></body></html>');
        return epubTextStyles(doc, ['div {$declaration}'])[doc.querySelector(
          'div',
        )]!;
      }

      final reset = styles(
        'background-image:url(local.png);'
        'background-size:20px;background:none repeat scroll 0 0 rgb(1, 2, 3)',
      );
      expect(reset['background-image'], 'none');
      expect(reset['background-size'], 'auto');
      expect(reset['background-color'], 'rgb(1, 2, 3)');
      expect(
        styles('background:#eee;background-color:red')['background-color'],
        'red',
      );
      expect(
        styles(
          'background:#eee!important;background-color:red',
        )['background-color'],
        '#eee',
      );
      expect(
        styles(
          'background-color:red!important;background:#eee',
        )['background-color'],
        'red',
      );
      for (final unsupported in [
        'linear-gradient(red,blue)',
        'red,blue',
        'red blue',
        'none repeat repeat scroll 0 0 #eee',
        'left right #eee',
        'var(--paper)',
        '#eee / cover',
        'none repeat scroll 0 #eee 0',
      ]) {
        expect(
          styles(
            'background-color:red;background:$unsupported',
          )['background-color'],
          'red',
          reason: unsupported,
        );
      }
    },
  );
}
