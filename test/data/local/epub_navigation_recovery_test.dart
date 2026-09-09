import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'epub_structure_test.dart' show parse, replace;
import 'support/epub_fixtures.dart';

void main() {
  test('nav labels preserve mixed text, image alt and accessible names', () {
    final files = epubFiles();
    replace(
      files,
      'OPS/nav.xhtml',
      '第一段',
      ' 第一 <span> 卷 </span><img alt="插图" title="不采用"/>\n目录 ',
    );
    replace(files, 'OPS/nav.xhtml', '第二卷', '<img alt="图片分组"/>');
    replace(
      files,
      'OPS/nav.xhtml',
      '第二段',
      '<span aria-label=" 可访问 标题 ">重复文字<img alt="重复图片"/></span>',
    );
    final nav = parse(files).content.navigation;
    expect(nav.first.title, '图片分组');
    expect(nav[1].title, '第一 卷 插图 目录');
    expect(nav[1].children.first.title, '可访问 标题');
    expect(nav[1].children.first.blockKey, isNotNull);
  });

  test('missing nav falls back to NCX', () {
    final files = epubFiles();
    files.remove('OPS/nav.xhtml');
    replace(
      files,
      'OPS/book.opf',
      '</manifest>',
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>',
    );
    expect(parse(files).content.navigation.first.title, '第二卷');
  });

  test('missing or malformed optional NCX falls back to spine', () {
    for (final ncx in [null, '<ncx><navMap>', '<wrong/>']) {
      final files = epubFiles(ncx: true);
      if (ncx == null) {
        files.remove('OPS/toc.ncx');
      } else {
        files['OPS/toc.ncx'] = utf8.encode(ncx);
      }
      final content = parse(files).content;
      expect(
        content.navigation.map((e) => e.chapterKey),
        content.chapters.map((e) => e.key),
      );
    }
  });

  test('optional navigation does not swallow entities or path escapes', () {
    for (final body in [
      '<!DOCTYPE ncx [<!ENTITY x "bad">]><ncx/>',
      '<ncx><navMap><navPoint><content src="../../escape"/></navPoint></navMap></ncx>',
    ]) {
      final files = epubFiles(ncx: true);
      files['OPS/toc.ncx'] = utf8.encode(body);
      expect(() => parse(files), throwsA(isA<LocalParseException>()));
    }
  });

  test('optional NCX still enforces XML depth budget', () {
    final files = epubFiles(ncx: true);
    files['OPS/toc.ncx'] = utf8.encode(
      '<ncx>${List.filled(140, '<x>').join()}${List.filled(140, '</x>').join()}</ncx>',
    );
    expect(() => parse(files), throwsA(isA<LocalParseException>()));
  });

  test(
    'metadata collapses XML whitespace without changing body or wide spaces',
    () {
      final files = epubFiles();
      final baseline = parse(files).content;
      replace(files, 'OPS/book.opf', '离线星空', ' \n离线\t 星空　番外\r\n ');
      replace(files, 'OPS/book.opf', '测试作者', ' 测试\n 作者 ');
      final content = parse(files).content;
      expect(content.detail.summary.title, '离线 星空　番外');
      expect(content.detail.summary.authors, ['测试 作者']);
      expect(
        content.chapters.first.blocks.map((e) => e.blockKey),
        baseline.chapters.first.blocks.map((e) => e.blockKey),
      );
    },
  );
}
