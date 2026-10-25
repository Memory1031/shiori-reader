import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

ParsedEpub book(
  String body, {
  String css = '',
  bool cover = false,
  int size = 32,
  String semantic = '',
}) {
  final files = epubFiles();
  files['OPS/images/ornament.png'] = fixturePng(size, size, 2);
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Original fixture</title><style>$css</style></head><body $semantic>$body</body></html>',
  );
  if (cover) {
    files['OPS/book.opf'] = utf8.encode(
      utf8
          .decode(files['OPS/book.opf']!)
          .replaceAll('images/星 空.png', 'images/ornament.png'),
    );
  }
  return EpubParser(
    zipFiles(files),
    NovelKey(sourceId: SourceId('local'), novelId: 'sizing'),
    'fixture.epub',
  ).parse();
}

void main() {
  String svg({
    String outer = '',
    String image = '',
    String extra = '',
    String view = '0 0 32 32',
  }) =>
      '<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="$view" $outer>'
      '<image width="32" height="32" href="../images/ornament.png" $image/>$extra</svg>';
  test(
    'simple SVG meet alignment stays independent of image size, role and identity',
    () {
      final centered = book(
        '<p>Before.</p>${svg()}<p>After.</p>',
      ).content.chapters.first;
      final left = book(
        '<p>Before.</p><div style="text-align:left">${svg()}</div><p>After.</p>',
      ).content.chapters.first;
      final c = centered.blocks.whereType<ImageBlock>().single;
      final l = left.blocks.whereType<ImageBlock>().single;
      expect(c.sizing!.alignment, ParagraphAlignment.center);
      expect(l.sizing!.alignment, ParagraphAlignment.start);
      expect(c.sizing!.role, ImageRole.flow);
      expect(c.sizing!.height, isNull);
      expect((c.width, c.height), (32, 32));
      expect(c.blockKey, l.blockKey);
      expect(centered.contentRevision, left.contentRevision);
      for (final entry in {
        'xMinYMid meet': ParagraphAlignment.start,
        'xMaxYMid meet': ParagraphAlignment.end,
      }.entries) {
        final b = book(
          '<p>Before.</p>${svg(outer: 'preserveAspectRatio="${entry.key}"')}',
        ).content.chapters.first.blocks.whereType<ImageBlock>().single;
        expect(b.sizing!.alignment, entry.value);
      }
      expect(
        ChapterContent.fromJson(jsonDecode(jsonEncode(centered.toJson()))),
        centered,
      );
    },
  );
  test('complex SVG and ordinary images do not acquire inferred centering', () {
    for (final markup in [
      svg(outer: 'transform="scale(2)"'),
      svg(image: 'x="1"'),
      svg(outer: 'preserveAspectRatio="none"'),
      svg(outer: 'preserveAspectRatio="xMidYMid slice"'),
      svg(view: '0 0 64 32'),
      svg(extra: '<path d="M0 0L32 32"/>'),
      svg(image: 'style="clip-path:url(#crop)"'),
      '<img src="../images/ornament.png"/>',
    ]) {
      final images = book(
        '<p>Before.</p>$markup<p>After.</p>',
      ).content.chapters.first.blocks.whereType<ImageBlock>();
      expect(images, isNotEmpty);
      expect(
        images.every((b) => b.sizing?.alignment == null),
        true,
        reason: markup,
      );
    }
  });
  test('HTML dimensions are display hints, not intrinsic raster dimensions', () {
    final result = book(
      '<p>Before</p><img width="40" height="20" src="../images/ornament.png"/><p>After</p>',
      size: 512,
    );
    final c = result.content.chapters.first;
    final b = c.blocks.whereType<ImageBlock>().single;
    expect((b.width, b.height), (512, 512));
    expect(b.layout!.widthLength, LayoutLength(40));
    expect(b.sizing!.height, LayoutLength(20));
    expect(b.sizing!.role, ImageRole.flow);
    expect(ChapterContent.fromJson(jsonDecode(jsonEncode(c.toJson()))), c);
  });
  test('CSS overrides HTML hints per axis, including auto and mixed units', () {
    ImageBlock get(String attributes, {String css = ''}) => book(
      '<p>Before</p><img $attributes src="../images/ornament.png"/><p>After</p>',
      css: css,
      size: 512,
    ).content.chapters.first.blocks.whereType<ImageBlock>().single;
    final sheet = get('width="40" height="20"', css: 'img{width:60px}');
    expect(sheet.layout!.widthLength, LayoutLength(60));
    expect(sheet.sizing!.height, LayoutLength(20));
    final inline = get('width="40" height="20" style="width:80px;height:auto"');
    expect(inline.layout!.widthLength, LayoutLength(80));
    expect(inline.sizing!.height, isNull);
    final reset = get('width="40" height="20" style="width:auto;height:auto"');
    expect(reset.layout?.widthLength, isNull);
    expect(reset.sizing!.height, isNull);
    final mixed = get('width="40" height="10" style="width:2em"');
    expect(mixed.layout!.widthLength, LayoutLength(2, LayoutUnit.em));
    expect(mixed.sizing!.height, LayoutLength(10));
    final percent = get('width="50%"');
    expect(percent.layout!.widthLength, LayoutLength(.5, LayoutUnit.fraction));
    expect(percent.sizing!.height, isNull);
    final height = get('height="40"');
    expect(height.layout?.widthLength, isNull);
    expect(height.sizing!.height, LayoutLength(40));
    for (final invalid in ['-1', 'NaN', '40px', '2em', '999999999']) {
      final b = get('width="$invalid" height="$invalid"');
      expect(b.layout?.widthLength, isNull, reason: invalid);
      expect(b.sizing!.height, isNull, reason: invalid);
    }
  });
  test(
    'unscaled block ornament retains alignment, margins, anchors and links',
    () {
      final result = book(
        '<p>Original opening.</p><div class="separator"><img id="ornament" src="../images/ornament.png"/></div><p><a href="#ornament">Return</a></p>',
        css: '.separator{text-align:center;margin:1em 0}',
      );
      final b = result.content.chapters.first.blocks
          .whereType<ImageBlock>()
          .single;
      expect((b.width, b.height), (32, 32));
      expect(b.sizing!.role, ImageRole.flow);
      expect(b.sizing!.alignment, ParagraphAlignment.center);
      expect(b.box!.margins!.top, LayoutLength(1, LayoutUnit.em));
      expect(result.content.links.single.targetBlockKey, b.blockKey);
    },
  );
  test('2em ornament keeps existing inline model and authored dimensions', () {
    final result = book(
      '<p>Before</p><div style="text-align:center"><img style="width:2em" alt="original" src="../images/ornament.png"/></div><p>After</p>',
      size: 88,
    );
    final blocks = result.content.chapters.first.blocks;
    expect(blocks.whereType<ImageBlock>(), isEmpty);
    final i = blocks.expand((b) => b.inlineImages).single;
    expect((i.widthEm, i.heightEm), (2, 2));
  });
  test(
    'height constraints are persisted separately from intrinsic pixel dimensions',
    () {
      final result = book(
        '<p>Before</p><img style="display:block;width:200px;height:100px;max-height:50%" src="../images/ornament.png"/><p>After</p>',
      );
      final b = result.content.chapters.first.blocks
          .whereType<ImageBlock>()
          .single;
      expect(b.layout!.widthLength, LayoutLength(200));
      expect(b.sizing!.height, LayoutLength(100));
      expect(b.sizing!.maxHeight, LayoutLength(.5, LayoutUnit.fraction));
      expect((b.width, b.height), (32, 32));
    },
  );
  test(
    'inline caps and explicit axes remain layout metadata with stable anchors',
    () {
      final p = book(
        '<p>Original <img style="width:2em;height:1em;max-width:20px;max-height:1em" src="../images/ornament.png"/> text.</p>',
      );
      final c = p.content.chapters.first;
      final i = c.blocks.expand((b) => b.inlineImages).single;
      expect(i.maxWidth, LayoutLength(20));
      expect(i.maxHeight, LayoutLength(1, LayoutUnit.em));
      expect(i.stretch, isTrue);
      expect(
        ChapterContent.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>,
        ),
        c,
      );
    },
  );
  test(
    'dedicated cover, structural illustration and fill get page role; bare icon does not',
    () {
      const img = '<img src="../images/ornament.png"/>';
      ImageBlock get(ParsedEpub p) =>
          p.content.chapters.first.blocks.whereType<ImageBlock>().single;
      expect(get(book(img)).sizing!.role, ImageRole.flow);
      expect(
        get(book(img, cover: true, size: 88)).sizing!.role,
        ImageRole.page,
      );
      expect(
        get(book(img, semantic: 'epub:type="loi"')).sizing!.role,
        ImageRole.page,
      );
      expect(
        get(book('<div style="width:100%">$img</div>')).sizing!.role,
        ImageRole.page,
      );
      expect(
        get(book('<div style="max-width:100%">$img</div>')).sizing!.role,
        ImageRole.flow,
      );
      expect(
        get(book('<p>Prose</p>$img', cover: true)).sizing!.role,
        ImageRole.flow,
      );
    },
  );
}
