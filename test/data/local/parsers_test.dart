import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shiori/features/reader/viewport/block_style.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_zip.dart';
import 'package:shiori/data/local/local_guard.dart';
import 'package:shiori/data/local/parser_worker.dart';
import 'package:shiori/data/local/txt/txt_decoder.dart';
import 'package:shiori/data/local/txt/txt_parser.dart';
import 'package:shiori/domain/contracts/cancellation.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'package:shiori/domain/models/models.dart';
import 'support/epub_fixtures.dart';

final key = LocalBookIdentity.book('a' * 64);
String original(LocalBookContent c) => c.chapters
    .expand((c) => c.blocks)
    .map(
      (b) => switch (b) {
        ParagraphBlock(:final text) || HeadingBlock(:final text) => text,
        _ => '',
      },
    )
    .join();
List<int> utf16(String text, {bool le = true}) => [
  ...le ? [255, 254] : [254, 255],
  for (final c in text.codeUnits) ...le ? [c & 255, c >> 8] : [c >> 8, c & 255],
];
Matcher problem(LocalParseProblem p) =>
    isA<LocalParseException>().having((e) => e.problem, 'problem', p);

class ParserSession implements LocalImportSession {
  ParserSession(this.bytes);
  final List<int> bytes;
  final media = <MediaRef, List<int>>{};
  @override
  NovelKey get key => LocalBookIdentity.book(sha256.convert(bytes).toString());
  @override
  Stream<List<int>> openOriginal() => Stream.value(bytes);
  @override
  Future<MediaRef> writeMedia(Stream<List<int>> stream) async {
    final value = await stream.expand((e) => e).toList();
    final ref = MediaRef(
      sourceId: key.sourceId,
      mediaId: '${key.novelId}/${sha256.convert(value)}',
    );
    media[ref] = value;
    return ref;
  }
}

Future<LocalBookContent> decode(
  ParserSession session,
  LocalBookFormat format, {
  CancellationToken? cancellation,
  TxtEncoding? encoding,
  ChooseTxtEncoding? choose,
}) => const BookDecoder().decode(
  session,
  format: format,
  filename: '原始文件.${format.name}',
  cancellation: cancellation ?? CancellationSource().token,
  encoding: encoding,
  chooseEncoding: choose ?? (p) async => p.samples.keys.first,
);

Uint8List unsafeZipName(String name) {
  final raw = utf8.encode(name);
  final b = zipFiles({
    'x' * raw.length: [1],
  });
  final d = ByteData.sublistView(b);
  final central = d.getUint32(b.length - 6, Endian.little);
  b.setRange(30, 30 + raw.length, raw);
  b.setRange(central + 46, central + 46 + raw.length, raw);
  return b;
}

void main() {
  group('TXT strict decoding and source identity', () {
    const source = '　序言\r\n\r\n原文😀\r\n第十二章 重名\n  正文\n第十二章 重名\r末尾\n';
    for (final e in TxtEncoding.values.where((e) => e != TxtEncoding.gb18030)) {
      test('${e.name} BOM and paragraph fidelity', () {
        final bytes = switch (e) {
          TxtEncoding.utf8 => [239, 187, 191, ...utf8.encode(source)],
          TxtEncoding.utf16le => utf16(source),
          _ => utf16(source, le: false),
        };
        expect(decodeTxt(bytes, e), source);
        final parsed = parseTxt(bytes, key, '文件.txt', e);
        expect(
          original(parsed),
          source.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
        );
        expect(parsed.detail.summary.title, '文件');
        expect(parsed.chapters.length, 3);
        expect(parsed.chapters.map((c) => c.key).toSet().length, 3);
        final offset = source
            .substring(0, source.lastIndexOf('第十二章'))
            .runes
            .length;
        expect(
          parsed.chapters.last.key,
          LocalBookIdentity.chapter(key, 'txt:$offset'),
        );
      });
    }
    test('GB18030 known GBK, four-byte BMP and supplementary vectors', () {
      expect(decodeGb18030([0xd6, 0xd0, 0xce, 0xc4]), '中文');
      expect(decodeGb18030([0x81, 0x30, 0x81, 0x30]), '\u0080');
      expect(decodeGb18030([0x90, 0x30, 0x81, 0x30]), '\u{10000}');
      expect(decodeGb18030([0x94, 0x39, 0xfc, 0x36]), '😀');
      expect(decodeGb18030([0xe3, 0x32, 0x9a, 0x35]), '\u{10ffff}');
      expect(decodeGb18030([0x80]), '€');
      expect(
        () => decodeGb18030([0xe3, 0x32, 0x9a, 0x36]),
        throwsFormatException,
      );
    });
    test(
      'illegal, truncated, surrogate and contradictory BOM fail strictly',
      () {
        for (final b in [
          [0xff],
          [0xe4, 0xb8],
          [0xc0, 0xaf],
          [0xed, 0xa0, 0x80],
        ]) {
          expect(
            () => decodeTxt(b, TxtEncoding.utf8),
            throwsA(problem(LocalParseProblem.encoding)),
          );
        }
        for (final b in [
          [0x81],
          [0x81, 0x30],
          [0x81, 0x30, 0x81],
          [0x81, 0x7f],
          [0x84, 0x32, 0xa5, 0x30],
        ]) {
          expect(
            () => decodeTxt(b, TxtEncoding.gb18030),
            throwsA(problem(LocalParseProblem.encoding)),
          );
        }
        for (final b in [
          [255, 254, 0],
          [255, 254, 0, 0xd8],
          [255, 254, 0, 0xdc],
          [254, 255, 0, 0x61],
        ]) {
          expect(
            () => decodeTxt(b, TxtEncoding.utf16le),
            throwsA(problem(LocalParseProblem.encoding)),
          );
        }
      },
    );
    test(
      'empty and binary fail; literal replacement character is preserved',
      () {
        expect(
          () => parseTxt([], key, 'x.txt', TxtEncoding.utf8),
          throwsA(problem(LocalParseProblem.invalid)),
        );
        expect(
          () => decodeTxt([0], TxtEncoding.utf8),
          throwsA(problem(LocalParseProblem.encoding)),
        );
        expect(decodeTxt(utf8.encode('原文�'), TxtEncoding.utf8), '原文�');
      },
    );
    test(
      'nonstandard chapter numbering, heading-only and no titles are readable',
      () {
        final c = parseTxt(
          utf8.encode('第两百零一章\n第２章\n終章'),
          key,
          'x.txt',
          TxtEncoding.utf8,
        );
        expect(c.chapters.length, 3);
        expect(original(c), '第两百零一章\n第２章\n終章');
        final one = parseTxt(
          utf8.encode('这不是标题，正文\n\n  有空白。'),
          key,
          'x.txt',
          TxtEncoding.utf8,
        );
        expect(one.chapters.length, 1);
        expect(original(one), '这不是标题，正文\n\n  有空白。');
      },
    );
    test('ambiguous suffix is not hidden by identical preview prefixes', () {
      final preview = inspectTxt(utf8.encode('A' * 700 + '中文'), null);
      expect(preview.samples.length, 2);
      expect(preview.samples.values.toSet().length, 2);
      expect(preview.detected, isNull);
    });
    test('long paragraph is never split into render chunks', () {
      final text = '长' * 200000;
      final c = parseTxt(utf8.encode(text), key, 'x.txt', TxtEncoding.utf8);
      expect(c.chapters.single.blocks.length, 1);
      expect(original(c), text);
    });
    test('unmarked GBK requires preview before publication', () async {
      var asked = false;
      final session = ParserSession([0xd6, 0xd0, 0xce, 0xc4]);
      final c = await decode(
        session,
        LocalBookFormat.txt,
        choose: (preview) async {
          asked = true;
          expect(preview.samples, {TxtEncoding.gb18030: '中文'});
          return TxtEncoding.gb18030;
        },
      );
      expect(asked, true);
      expect(original(c), '中文');
    });
    test(
      'ASCII and UTF8 BOM need no ambiguous-encoding confirmation',
      () async {
        for (final b in [
          utf8.encode('plain text'),
          [239, 187, 191, ...utf8.encode('中文')],
        ]) {
          await decode(
            ParserSession(b),
            LocalBookFormat.txt,
            choose: (_) async => throw StateError('Unexpected prompt'),
          );
        }
      },
    );
    test(
      'manual encoding gives preview and validates the whole file',
      () async {
        final text = 'A' * 1000 + '中文';
        var asked = false;
        final c = await decode(
          ParserSession(utf8.encode(text)),
          LocalBookFormat.txt,
          encoding: TxtEncoding.utf8,
          choose: (p) async {
            asked = true;
            expect(p.samples.values.single.length, 600);
            return TxtEncoding.utf8;
          },
        );
        expect(asked, true);
        expect(original(c), text);
        expect(
          () =>
              inspectTxt([...utf8.encode('A' * 1000), 0xff], TxtEncoding.utf8),
          throwsA(problem(LocalParseProblem.encoding)),
        );
      },
    );
    test(
      'large input is rejected before decoding and worker cancellation exits',
      () async {
        await expectLater(
          decode(
            ParserSession(Uint8List(BookDecoder.maxTxtBytes + 1)),
            LocalBookFormat.txt,
          ),
          throwsA(problem(LocalParseProblem.tooLarge)),
        );
        final cancellation = CancellationSource();
        final future = runParserWorker(() {
          var n = 0;
          while (true) {
            n++;
            if (n < 0) return n;
          }
        }, cancellation.token);
        final assertion = expectLater(future, throwsA(isA<LocalCancelled>()));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        cancellation.cancel();
        await assertion.timeout(const Duration(seconds: 3));
        expect(await runParserWorker(() => 42, CancellationSource().token), 42);
      },
    );
  });

  test(
    'real large TXT decoding can be cancelled without a late result',
    () async {
      final source = CancellationSource();
      final future = decode(
        ParserSession(utf8.encode('长段落' * 300000)),
        LocalBookFormat.txt,
        cancellation: source.token,
      );
      final assertion = expectLater(future, throwsA(isA<LocalCancelled>()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      source.cancel();
      await assertion.timeout(const Duration(seconds: 3));
    },
  );

  group('EPUB package, content and navigation', () {
    for (final ncx in [false, true]) {
      test(
        '${ncx ? 'EPUB2 NCX' : 'EPUB3 nav'} preserves spine, nested TOC and anchors',
        () {
          final parsed = EpubParser(
            zipFiles(epubFiles(ncx: ncx)),
            key,
            'x.epub',
          ).parse();
          final c = parsed.content;
          expect(c.detail.summary.title, '离线星空');
          expect(c.detail.summary.authors, ['测试作者']);
          expect(c.chapters.first.title, '第一章 星海');
          expect(c.chapters.last.title, '第二章');
          expect(
            c.catalog.flatChapters.map((e) => e.key),
            c.chapters.map((e) => e.key),
          );
          expect(c.navigation.first.chapterKey, c.chapters.last.key);
          expect(
            c.navigation.first.children.single.title,
            ncx ? '第二章' : '先列第二章',
          );
          final a = c.navigation.last;
          expect(a.chapterKey, c.chapters.first.key);
          final target =
              c.chapters.first.blocks.firstWhere(
                    (b) => b.blockKey == a.blockKey,
                  )
                  as ParagraphBlock;
          expect(target.text, '一段强调，こんにちは。');
          expect(a.children.first.blockKey, isNot(a.blockKey));
          expect(a.children.last.blockKey, isNull);
          expect(parsed.media.length, 1);
          expect(
            c.detail.summary.cover,
            c.chapters.first.blocks.whereType<ImageBlock>().single.media,
          );
          expect(c.chapters.first.blocks.whereType<DividerBlock>().length, 1);
        },
      );
    }
    test('EPUB2 external NCX doctype is ignored without network access', () {
      final files = epubFiles(ncx: true);
      files['OPS/toc.ncx'] = utf8.encode(
        '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">${utf8.decode(files['OPS/toc.ncx']!)}',
      );
      expect(
        EpubParser(zipFiles(files), key, 'x').parse().content.navigation.length,
        2,
      );
    });
    test('no TOC generates spine-ordered navigation', () {
      final c = EpubParser(
        zipFiles(epubFiles(toc: false)),
        key,
        'x.epub',
      ).parse().content;
      expect(
        c.navigation.map((n) => n.chapterKey),
        c.chapters.map((n) => n.key),
      );
    });
    test(
      'fragment inside inline content maps to its actual containing paragraph',
      () {
        final files = epubFiles();
        files['OPS/text/a.xhtml'] = utf8.encode(
          '<html><body><p>before <span id="one">middle</span> after</p><p id="two">next</p></body></html>',
        );
        final c = EpubParser(zipFiles(files), key, 'x.epub').parse().content;
        expect(
          c.navigation.last.blockKey,
          c.chapters.first.blocks.first.blockKey,
        );
        expect(
          (c.chapters.first.blocks.first as ParagraphBlock).text,
          'before middle after',
        );
      },
    );
    for (final attribute in ['xlink:href', 'href']) {
      test('SVG raster image resolves $attribute without a placeholder', () {
        final files = epubFiles();
        files['OPS/text/a.xhtml'] = utf8.encode(
          '<html><body><figure><svg xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 10 10">'
          '<image $attribute="../images/星%20空.png" width="10" height="10"/>'
          '</svg></figure></body></html>',
        );
        final parsed = EpubParser(zipFiles(files), key, 'svg.epub').parse();
        final blocks = parsed.content.chapters.first.blocks;
        expect(blocks, hasLength(1));
        expect(blocks.single, isA<ImageBlock>());
        expect(
          (blocks.single as ImageBlock).media,
          parsed.content.detail.summary.cover,
        );
      });
    }
    test(
      'HTML source whitespace does not suppress CSS first-line indentation',
      () {
        final files = epubFiles();
        files['OPS/text/a.xhtml'] = utf8.encode(
          '<html><head><style>p {text-indent:2em}</style></head><body>'
          '<p>\n    正文<strong>强调</strong> english words.\n </p>'
          '<p>　　全角缩进</p><p>&nbsp;&nbsp;不换行空格</p>'
          '<pre>  保留\n 空白  </pre></body></html>',
        );
        final blocks = EpubParser(zipFiles(files), key, 'indent.epub')
            .parse()
            .content
            .chapters
            .first
            .blocks
            .whereType<ParagraphBlock>()
            .toList();
        expect(blocks[0].text, '正文强调 english words.');
        expect(blocks[0].leadingIndent, 2);
        String indent(int i, bool first) => readerIndentPrefix(
          blocks[i],
          first,
          350,
          const TextStyle(fontSize: 20),
          TextScaler.noScaling,
          chapter: ChapterKey(novelKey: key, chapterId: 'test'),
        );
        expect(indent(0, true), '\u2003\u2003');
        expect(indent(0, false), isEmpty);
        expect(blocks[1].text, '　　全角缩进');
        expect(indent(1, true), isEmpty);
        expect(blocks[2].text, '\u00a0\u00a0不换行空格');
        expect(blocks[3].text, '  保留\n 空白  ');
      },
    );
    test('missing and remote images isolate failure; scripts are not text', () {
      final files = epubFiles();
      files.remove('OPS/images/星 空.png');
      files['OPS/text/b.xhtml'] = utf8.encode(
        '<html><body><p>safe</p><script>throw secret</script><iframe src="https://invalid.test">unsafe</iframe><img src="https://invalid.test/image.png"/><p>after</p></body></html>',
      );
      final result = EpubParser(zipFiles(files), key, 'x.epub').parse();
      expect(result.media, isEmpty);
      expect(result.content.detail.summary.cover, isNull);
      expect(original(result.content), contains('safe[▧]after'));
      expect(original(result.content), isNot(contains('secret')));
      expect(original(result.content), isNot(contains('unsafe')));
    });
    test(
      'DRM and fixed layouts are distinctly rejected; obfuscated fonts ignored',
      () {
        final files = epubFiles();
        files['META-INF/encryption.xml'] = utf8.encode(
          '<encryption><EncryptedData><EncryptionMethod Algorithm="DRM"/><CipherReference URI="OPS/text/a.xhtml"/></EncryptedData></encryption>',
        );
        expect(
          () => EpubParser(zipFiles(files), key, 'x').parse(),
          throwsA(problem(LocalParseProblem.drm)),
        );
        files['META-INF/encryption.xml'] = utf8.encode(
          '<encryption><EncryptedData><EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/><CipherReference URI="OPS/font.ttf"/></EncryptedData></encryption>',
        );
        expect(
          EpubParser(zipFiles(files), key, 'x').parse().content.chapters.length,
          2,
        );
        files['OPS/book.opf'] = utf8.encode(
          utf8
              .decode(files['OPS/book.opf']!)
              .replaceFirst('<metadata ', '<metadata ')
              .replaceFirst(
                '</metadata>',
                '<meta property="rendition:layout">pre-paginated</meta></metadata>',
              ),
        );
        expect(
          () => EpubParser(zipFiles(files), key, 'x').parse(),
          throwsA(problem(LocalParseProblem.fixedLayout)),
        );
      },
    );
    test('package references stay contained and decode Unicode once', () {
      expect(
        epubReference(
          'OPS/text/a.xhtml',
          '../images/%E6%98%9F%20%E7%A9%BA.png#x',
        ),
        ('OPS/images/星 空.png', 'x'),
      );
      expect(epubReference('OPS/a.xhtml', '#one'), ('OPS/a.xhtml', 'one'));
      for (final r in [
        'https://invalid.test/a',
        '//invalid.test/a',
        'data:text/plain,x',
      ]) {
        expect(epubReference('OPS/a', r), isNull);
      }
      for (final r in [
        '../../escape',
        '%2e%2e/%2e%2e/escape',
        '/escape',
        '%5cescape',
      ]) {
        expect(
          () => epubReference('OPS/a', r),
          throwsA(problem(LocalParseProblem.invalid)),
        );
      }
    });
    test('DTD entity expansion and deeply nested markup are rejected', () {
      final files = epubFiles();
      files['META-INF/container.xml'] = utf8.encode(
        '<!DOCTYPE x [<!ENTITY x "abc">]><x>&x;</x>',
      );
      expect(
        () => EpubParser(zipFiles(files), key, 'x').parse(),
        throwsA(problem(LocalParseProblem.invalid)),
      );
      final deep = epubFiles();
      deep['OPS/text/a.xhtml'] = utf8.encode(
        '<html><body>${'<div>' * 130}text${'</div>' * 130}</body></html>',
      );
      expect(
        () => EpubParser(zipFiles(deep), key, 'x').parse(),
        throwsA(problem(LocalParseProblem.tooLarge)),
      );
    });
    test(
      'real decoder writes hash-addressed images through the session',
      () async {
        final session = ParserSession(zipFiles(epubFiles()));
        final c = await decode(session, LocalBookFormat.epub);
        expect(session.media[c.detail.summary.cover], tinyPng);
        expect(
          c.chapters.first.key,
          LocalBookIdentity.chapter(session.key, 'epub:OPS/text/a.xhtml'),
        );
      },
    );
  });

  group('ZIP bounded decoding', () {
    test('stored and deflate bytes are verified by CRC', () {
      for (final compressed in [false, true]) {
        final b = zipFiles({'a': utf8.encode('payload')}, compress: compressed);
        expect(utf8.decode(EpubZip(b).read('a')), 'payload');
        final damaged = Uint8List.fromList(b);
        final data = ByteData.sublistView(damaged);
        final central = data.getUint32(damaged.length - 6, Endian.little);
        data.setUint32(14, 0, Endian.little);
        data.setUint32(central + 16, 0, Endian.little);
        expect(() => EpubZip(damaged).read('a'), throwsA(anything));
      }
    });
    test('truncation, traversal, absolute paths and symlinks fail', () {
      for (final path in [
        '../evil',
        '/evil',
        'a/../../evil',
        'a\\evil',
        'C:/evil',
        'a/./b',
      ]) {
        expect(
          () => EpubZip(unsafeZipName(path)),
          throwsA(problem(LocalParseProblem.invalid)),
        );
      }
      final b = zipFiles({
        'a': [1],
      });
      expect(
        () => EpubZip(Uint8List.sublistView(b, 0, b.length - 1)),
        throwsA(anything),
      );
      final d = ByteData.sublistView(b);
      final central = d.getUint32(b.length - 6, Endian.little);
      d.setUint32(central + 38, 0xa1ff << 16, Endian.little);
      expect(() => EpubZip(b), throwsA(problem(LocalParseProblem.invalid)));
    });
    test(
      'entry count, declared sizes, ratio and actual expansion are bounded',
      () {
        expect(
          () => EpubZip(
            zipFiles({
              for (var i = 0; i < 4097; i++) '$i': [1],
            }),
          ),
          throwsA(problem(LocalParseProblem.tooLarge)),
        );
        expect(
          () => EpubZip(zipFiles({'a': Uint8List(4 * 1024 * 1024)})),
          throwsA(problem(LocalParseProblem.tooLarge)),
        );
        final b = zipFiles({'a': Uint8List(10000)});
        final d = ByteData.sublistView(b);
        final central = d.getUint32(b.length - 6, Endian.little);
        d.setUint32(22, 1, Endian.little);
        d.setUint32(central + 24, 1, Endian.little);
        expect(
          () => EpubZip(b).read('a'),
          throwsA(problem(LocalParseProblem.tooLarge)),
        );
        d.setUint32(22, EpubZip.maxEntry + 1, Endian.little);
        d.setUint32(central + 24, EpubZip.maxEntry + 1, Endian.little);
        expect(() => EpubZip(b), throwsA(problem(LocalParseProblem.tooLarge)));
      },
    );
  });
}
