import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';
import 'support/synthetic_font.dart';

void main() {
  final key = LocalBookIdentity.book('a' * 64);
  test(
    'author fonts follow inheritance and remain independent of semantic identity',
    () {
      final files = epubFiles();
      files['OPS/fonts/narrow.ttf'] = syntheticFont(advance: 400);
      files['OPS/fonts/wide.ttf'] = syntheticFont(advance: 900);
      files['OPS/styles/font.css'] = utf8.encode(
        '@font-face{font-family:"Book Narrow";src:url(../fonts/narrow.ttf)} @font-face{font-family:wide;src:url(../fonts/wide.ttf)} body{font-family:"Book Narrow"} h1{font-family:wide} .reset{font-family:initial;color:blue} .inherit{font-family:inherit}',
      );
      files['OPS/text/a.xhtml'] = utf8.encode(
        '<html><head><link rel="stylesheet" href="../styles/font.css"/></head><body><h1 id="h">Title</h1><p>A<span style="color:red">B</span><span class="reset">C</span><span class="inherit">D</span></p><p><a href="#h">Jump</a></p></body></html>',
      );
      final parsed = EpubParser(zipFiles(files), key, 'synthetic.epub').parse();
      final chapter = parsed.content.chapters.first,
          heading = chapter.blocks.first as HeadingBlock,
          body = chapter.blocks[1] as ParagraphBlock;
      final headingFonts = heading.inlineStyles.single.fonts;
      expect(headingFonts, hasLength(1));
      expect(body.inlineStyles.map((s) => s.fonts.isNotEmpty), [
        true,
        true,
        false,
        true,
      ]);
      expect(body.inlineStyles[0].fonts, body.inlineStyles[1].fonts);
      expect(headingFonts, isNot(body.inlineStyles[0].fonts));
      expect(
        chapter.blocks[2].inlineStyles.single.fonts,
        body.inlineStyles[0].fonts,
      );
      expect(parsed.content.chapters[1].blocks.first.inlineStyles, isEmpty);
      expect(body.blockKey, ParagraphBlock(text: 'ABCD').blockKey);
      expect(parsed.content.links.single.sourceLength, 4);
      expect(ChapterContent.fromJson(chapter.toJson()), chapter);
      expect(body.mediaRefs, isNotEmpty);
    },
  );
  test('single background decoration preserves text and resource separately', () {
    final files = epubFiles();
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><link rel="stylesheet" href="../styles/theme.css"/></head><body><p id="n" class="badge">2</p><p>Tail</p><p><a href="#n">Back</a></p></body></html>',
    );
    files['OPS/styles/theme.css'] = utf8.encode(
      '.badge{background:url(../images/badge.png) no-repeat center;background-size:2.2em;padding:1.2em 20px .3em;text-align:center;color:#ffeeee}',
    );
    files['OPS/images/badge.png'] = tinyPng;
    final parsed = EpubParser(zipFiles(files), key, 'synthetic.epub').parse();
    final chapter = parsed.content.chapters.first;
    final block = chapter.blocks.first as ParagraphBlock;
    expect(block.text, '2');
    expect(block.inlineImages, isEmpty);
    expect(chapter.blocks.whereType<ImageBlock>(), isEmpty);
    expect(block.toJson()['box'], contains('backgroundImage'));
    expect(block.mediaRefs, isNotEmpty);
    expect(parsed.content.links.single.targetBlockKey, block.blockKey);
    expect(
      block.blockKey,
      ParagraphBlock(text: '2', alignment: ParagraphAlignment.center).blockKey,
    );
    expect(ChapterContent.fromJson(chapter.toJson()), chapter);
  });
  test('font faces are scoped, optional and selected only by author CSS', () {
    final files = epubFiles();
    files['OPS/fonts/Face.TTF'] = syntheticFont();
    files['OPS/fonts/bad.ttf'] = [1, 2, 3];
    files['OPS/styles/font.css'] = utf8.encode(
      '@media screen {@font-face{font-family:book;src:url(../fonts/missing.ttf),url(../fonts/Face.TTF)}} @font-face{font-family:bad;src:url(../fonts/bad.ttf)} .book{font-family:book} .bad{font-family:bad}',
    );
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><link rel="stylesheet" href="../styles/font.css"/></head><body><p>Default</p><p class="book">Book</p><p class="bad">Fallback</p><p style="font-family:Missing, book">List</p></body></html>',
    );
    final first = EpubParser(
      zipFiles(files),
      key,
      'synthetic.epub',
    ).parse().content.chapters.first;
    final other = EpubParser(
      zipFiles(files),
      LocalBookIdentity.book('b' * 64),
      'synthetic.epub',
    ).parse().content.chapters.first;
    expect(first.blocks[0].inlineStyles, isEmpty);
    expect(first.blocks[1].inlineStyles.single.fonts, hasLength(1));
    expect(first.blocks[2].inlineStyles, isEmpty);
    expect(
      first.blocks[3].inlineStyles.single.fonts,
      first.blocks[1].inlineStyles.single.fonts,
    );
    expect(
      first.blocks[1].inlineStyles.single.fonts.single.familyName,
      isNot(other.blocks[1].inlineStyles.single.fonts.single.familyName),
    );
    expect(
      first.blocks.map((b) => b.blockKey),
      other.blocks.map((b) => b.blockKey),
    );
  });
  test('background cascade keeps case-sensitive URLs and can reset decoration', () {
    final files = epubFiles();
    files['OPS/images/Badge.PNG'] = tinyPng;
    files['OPS/styles/bg.css'] = utf8.encode(
      '.b{background:url(../images/Badge.PNG) no-repeat center;background-size:2em !IMPORTANT} .off{background-image:NONE}',
    );
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><head><link rel="stylesheet" href="../styles/bg.css"/></head><body><div style="border:1px solid blue"><p class="b">2</p></div><p class="b off">3</p></body></html>',
    );
    final chapter = EpubParser(
      zipFiles(files),
      key,
      'synthetic.epub',
    ).parse().content.chapters.first;
    expect(chapter.blocks.first.box!.backgroundImage, isNull);
    expect(
      chapter.blocks.first.layout!.backgroundImage!.width,
      LayoutLength(2, LayoutUnit.em),
    );
    expect(chapter.blocks[1].box?.backgroundImage, isNull);
    expect(chapter.blocks[1].layout?.backgroundImage, isNull);
  });
  test('decorated links retain their own background and click geometry', () {
    final files = epubFiles();
    files['OPS/images/badge.png'] = tinyPng;
    files['OPS/text/a.xhtml'] = utf8.encode(
      '<html><body><p style="background-image:url(../images/badge.png);background-repeat:no-repeat;background-color:blue;padding:1em"><a href="#tail">Badge</a></p><p id="tail">Tail</p></body></html>',
    );
    final parsed = EpubParser(zipFiles(files), key, 'synthetic.epub').parse();
    final block = parsed.content.chapters.first.blocks.first as ParagraphBlock;
    expect(block.linkDecoration, isNotNull);
    expect(block.box?.backgroundImage, isNull);
    expect(block.text, 'Badge');
    expect(parsed.content.links.single.sourceLength, 5);
  });
  for (final suffix in [
    'background-repeat:repeat',
    'background-attachment:fixed',
    'background-origin:content-box',
    'background-clip:text',
    'background-size:cover',
    'background-size:20px 40px',
  ]) {
    test(
      'unsupported background geometry falls back without losing text ($suffix)',
      () {
        final files = epubFiles();
        files['OPS/images/badge.png'] = tinyPng;
        files['OPS/text/a.xhtml'] = utf8.encode(
          '<html><body><p style="background:url(../images/badge.png) no-repeat center;$suffix">2</p><p>Tail</p></body></html>',
        );
        final chapter = EpubParser(
          zipFiles(files),
          key,
          'synthetic.epub',
        ).parse().content.chapters.first;
        expect(chapter.blocks.whereType<ParagraphBlock>().map((b) => b.text), [
          '2',
          'Tail',
        ]);
        expect(chapter.blocks.first.box?.backgroundImage, isNull);
      },
    );
  }
}
