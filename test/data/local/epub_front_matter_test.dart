import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/local_chapter_progress.dart';
import 'epub_structure_test.dart' show parse;
import 'support/epub_fixtures.dart';

String page(String title, String body, {String type = ''}) =>
    '<html xmlns:epub="http://www.idpf.org/2007/ops"><head><title>$title</title>'
    '</head><body epub:type="$type">$body</body></html>';
const picture = '<img src="../images/%E6%98%9F%20%E7%A9%BA.png"/>';

Map<String, List<int>> frontMatterFiles(
  Map<String, String> pages, {
  Map<String, String> entries = const {'a': 'First', 'b': 'Second'},
  String? tree,
  String guide = '',
  String landmarks = '',
  bool ncx = false,
  String spine = '',
}) {
  final files = epubFiles(ncx: ncx);
  files['OPS/book.opf'] = utf8.encode('''
    <package xmlns="http://www.idpf.org/2007/opf" version="${ncx ? '2.0' : '3.0'}">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
      <dc:title>离线星空</dc:title><dc:creator>测试作者</dc:creator>
      <meta name="cover" content="image"/>
    </metadata><manifest>
      <item id="image" href="images/星 空.png" media-type="image/png"/>
      ${pages.keys.map((p) => '<item id="$p" href="text/$p.xhtml" media-type="application/xhtml+xml"/>').join()}
      <item id="nav" href="${ncx ? 'toc.ncx' : 'nav.xhtml'}"
        media-type="${ncx ? 'application/x-dtbncx+xml' : 'application/xhtml+xml'}"
        ${ncx ? '' : 'properties="nav"'}/>
    </manifest><spine ${ncx ? 'toc="nav"' : ''}>
      ${spine.isNotEmpty ? spine : pages.keys.map((p) => '<itemref idref="$p"/>').join()}
    </spine>${guide.isEmpty ? '' : '<guide>$guide</guide>'}</package>''');
  if (ncx) {
    files['OPS/toc.ncx'] = utf8.encode(
      '<ncx><navMap>${entries.entries.map((e) => '<navPoint><navLabel><text>${e.value}</text></navLabel>'
          '<content src="text/${e.key}.xhtml"/></navPoint>').join()}</navMap></ncx>',
    );
  } else {
    files['OPS/nav.xhtml'] = utf8.encode(
      '<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
      '<nav epub:type="toc"><ol>${tree ?? entries.entries.map((e) => '<li><a href="text/${e.key}.xhtml">${e.value}</a></li>').join()}</ol></nav>$landmarks</body></html>',
    );
  }
  for (final entry in pages.entries) {
    files['OPS/text/${entry.key}.xhtml'] = utf8.encode(entry.value);
  }
  return files;
}

List<LocalNavigationEntry> flat(List<LocalNavigationEntry> entries) => [
  for (final entry in entries) ...[entry, ...flat(entry.children)],
];

void main() {
  for (final ncx in [false, true]) {
    test(
      'supplements multi-volume front matter with ${ncx ? 'NCX' : 'nav'}',
      () {
        final content = parse(
          frontMatterFiles({
            'cover': page('Cover', picture),
            'title': page('未知', '<p>离线星空 1</p><p>测试作者</p>'),
            'credits': page('制作信息', '<p>翻译与制作名单。</p>'),
            'summary': page('简介', '<p>一段简介。</p>'),
            'art1': page('彩插', picture),
            'art2': page('彩插', picture),
            'toc1': page('目录', picture),
            'toc2': page('目录', '<p>First · Second</p>'),
            'a': page('第一章', '<p id="body">第一章开头。</p>'),
            'continuation': page('离线星空', '<p>同章续篇。</p>'),
            'bodyImage': page('未知', picture),
            'cover2': page('Cover', picture),
            'summary2': page('内容简介', '<p>第二卷简介。</p>'),
            'b': page('第二章', '<p>第二章正文。</p>'),
          }, ncx: ncx),
        ).content;
        expect(flat(content.navigation).map((e) => e.title), [
          'Cover',
          'Title page',
          '制作信息',
          '简介',
          '彩插',
          '目录',
          'First',
          'Cover',
          '内容简介',
          'Second',
        ]);
        final index = LocalChapterProgressIndex.build(
          metrics: content.progressMetrics,
          chapters: content.chapters,
          navigation: content.navigation,
        )!;
        LocalChapterSection section(int document) =>
            index.sectionAt(content.chapters[document].key, null)!;
        expect(section(4), same(section(5)));
        expect(section(6), same(section(7)));
        expect(section(8), same(section(9)));
        expect(section(8), same(section(10)));
        expect(section(11).title, 'Cover');
        expect(index.target(section(8), 1).chapter, content.chapters[10].key);
        expect(index.target(section(4), 1).chapter, content.chapters[5].key);
        expect(index.target(section(6), 1).chapter, content.chapters[7].key);
        expect(
          flat(content.navigation).map((e) => e.chapterKey).toSet(),
          hasLength(content.navigation.length),
        );
      },
    );
  }

  test(
    'retains nested authored labels and fragment targets without duplicates',
    () {
      final content = parse(
        frontMatterFiles(
          {
            'cover': page('Cover', picture),
            'summary': page('简介', '<p id="summary">简介内容。</p>'),
            'a': page('First', '<p id="one">开头。</p><p id="two">第二段。</p>'),
            'credits': page('制作信息', '<p>第二卷制作信息。</p>'),
            'b': page('Second', '<p>下一章。</p>'),
          },
          tree:
              '''<li><a href="text/summary.xhtml#summary">Original volume</a><ol>
      <li><a href="text/summary.xhtml#summary">Existing introduction</a></li>
      <li><a href="text/a.xhtml#two">Original fragment</a></li>
      <li><a href="text/b.xhtml">Original next</a></li></ol></li>''',
        ),
      ).content;
      final entries = flat(content.navigation);
      expect(entries.map((e) => e.title), [
        'Cover',
        'Original volume',
        'Existing introduction',
        'Original fragment',
        '制作信息',
        'Original next',
      ]);
      expect(content.navigation[1].children.map((e) => e.title), [
        'Existing introduction',
        'Original fragment',
        '制作信息',
        'Original next',
      ]);
      expect(entries[3].blockKey, content.chapters[2].blocks[1].blockKey);
      expect(entries.where((e) => e.title == '简介'), isEmpty);
    },
  );

  test(
    'preserves authored TOC order even when it differs from spine order',
    () {
      final content = parse(
        frontMatterFiles(
          {
            'cover': page('Cover', picture),
            'a': page('A', '<p>First.</p>'),
            'credits': page('Credits', '<p>Names.</p>'),
            'b': page('B', '<p>Second.</p>'),
          },
          entries: {'b': 'Second', 'a': 'First'},
        ),
      ).content;
      expect(content.navigation.map((e) => e.title), [
        'Credits',
        'Second',
        'Cover',
        'First',
      ]);
    },
  );

  test(
    'generic titles, body semantics and long prose do not create chapters',
    () {
      final content = parse(
        frontMatterFiles({
          'a': page('First', '<p>正文开头。</p>'),
          'continuation': page('离线星空', '<p>正文续篇。</p>'),
          'bodyImage': page('未知', picture),
          'body': page('Synopsis', '<p>正文中的一段。</p>', type: 'chapter'),
          'long': page('Preface', '<p>${'This is body prose. ' * 300}</p>'),
          'b': page('Second', '<p>下一章。</p>'),
        }),
      ).content;
      expect(content.navigation.map((e) => e.title), ['First', 'Second']);
      final index = LocalChapterProgressIndex.build(
        metrics: content.progressMetrics,
        chapters: content.chapters,
        navigation: content.navigation,
      )!;
      for (final chapter in content.chapters.take(5)) {
        expect(index.sectionAt(chapter.key, null)!.title, 'First');
      }
    },
  );

  test('guide and namespace-aware landmarks classify only whole documents', () {
    final content = parse(
      frontMatterFiles(
        {
          'cover': page('未知', picture),
          'summary': page('未知', '<p>Summary content.</p>'),
          'a': page(
            'First',
            '<p>Body start.</p><p id="inside">Inside body.</p>',
          ),
          'b': page('Second', '<p>Next.</p>'),
        },
        guide:
            '<reference type="cover" title="Book jacket" href="text/cover.xhtml"/>',
        landmarks:
            '''<nav xmlns:book="http://www.idpf.org/2007/ops" book:type="landmarks"><ol>
      <li><a book:type="abstract" href="text/summary.xhtml">About this volume</a></li>
      <li><a book:type="preface" href="text/a.xhtml#inside">Not a whole page</a></li>
      <li><a book:type="cover" href="../../outside">Invalid optional landmark</a></li>
      </ol></nav>''',
      ),
    ).content;
    expect(content.navigation.map((e) => e.title), [
      'Book jacket',
      'About this volume',
      'First',
      'Second',
    ]);
  });

  test('document semantics require correct namespace and enclosing scope', () {
    final content = parse(
      frontMatterFiles({
        'cover':
            '<html xmlns:x="http://www.idpf.org/2007/ops"><body x:type="cover">$picture</body></html>',
        'foreign':
            '<html xmlns:x="urn:foreign"><body x:type="cover">$picture</body></html>',
        'mixed': page(
          'Unknown',
          '<div epub:type="abstract"><p>Abstract.</p></div><p>Body.</p>',
        ),
        'a': page('First', '<p>正文。</p>'),
        'b': page('Second', '<p>下一章。</p>'),
      }),
    ).content;
    expect(content.navigation.map((e) => e.title), [
      'Cover',
      'First',
      'Second',
    ]);
  });

  test(
    'existing illustration run owns unlabelled images and fullwidth contents',
    () {
      final content = parse(
        frontMatterFiles(
          {
            'art': page('Unknown', picture),
            'moreArt': page('Unknown', picture),
            'toc': page('Unknown', '<p>Ｃｏｎｔｅｎｔｓ</p><p>First and Second</p>'),
            'a': page('A', '<p>First.</p>'),
            'b': page('B', '<p>Second.</p>'),
          },
          entries: {'art': '彩页', 'a': 'First', 'b': 'Second'},
        ),
      ).content;
      expect(content.navigation.map((e) => e.title), [
        '彩页',
        'Ｃｏｎｔｅｎｔｓ',
        'First',
        'Second',
      ]);
      final index = LocalChapterProgressIndex.build(
        metrics: content.progressMetrics,
        chapters: content.chapters,
        navigation: content.navigation,
      )!;
      expect(
        index.target(index.sections.first, 1).chapter,
        content.chapters[1].key,
      );
    },
  );

  test('repeated EPUB 3 cover occurrences retain independent navigation', () {
    final content = parse(
      frontMatterFiles(
        {
          'cover': page('Cover', picture),
          'a': page('A', '<p>First.</p>'),
          'b': page('B', '<p>Second.</p>'),
        },
        spine:
            '<itemref idref="cover"/><itemref idref="a"/>'
            '<itemref idref="cover"/><itemref idref="b"/>',
      ),
    ).content;
    expect(content.navigation.map((e) => e.title), [
      'Cover',
      'First',
      'Cover',
      'Second',
    ]);
    expect(
      content.navigation[0].chapterKey,
      isNot(content.navigation[2].chapterKey),
    );
  });

  test('guide semantics apply to repeated sources without duplicating TOC', () {
    final content = parse(
      frontMatterFiles(
        {
          'cover': page('未知', picture),
          'a': page('A', '<p>First.</p>'),
          'b': page('B', '<p>Second.</p>'),
        },
        entries: {'cover': 'Original jacket', 'a': 'First', 'b': 'Second'},
        guide: '<reference type="cover" href="text/cover.xhtml"/>',
        spine:
            '<itemref idref="cover"/><itemref idref="a"/>'
            '<itemref idref="cover"/><itemref idref="b"/>',
      ),
    ).content;
    expect(content.navigation.map((e) => e.title), [
      'Original jacket',
      'First',
      'Cover',
      'Second',
    ]);
    expect(content.navigation.map((e) => e.chapterKey).toSet(), hasLength(4));
  });

  test('nonlinear pages keep access without swallowing primary groups', () {
    final content = parse(
      frontMatterFiles(
        {
          'a': page('A', '<p>First.</p>'),
          'aux1': page('彩插', picture),
          'aux2': page('彩插', picture),
          'art': page('彩插', picture),
          'b': page('B', '<p>Next.</p>'),
        },
        spine:
            '<itemref idref="a"/><itemref idref="aux1" linear="no"/>'
            '<itemref idref="aux2" linear="no"/><itemref idref="art"/>'
            '<itemref idref="b"/>',
      ),
    ).content;
    expect(content.navigation.map((e) => e.title), [
      'First',
      '彩插',
      '彩插',
      '彩插',
      'Second',
    ]);
    final index = LocalChapterProgressIndex.build(
      metrics: content.progressMetrics,
      chapters: content.chapters,
      navigation: content.navigation,
    )!;
    expect(index.sections.map((s) => s.title), ['First', '彩插', 'Second']);
    expect(index.sectionAt(content.chapters[3].key, null)!.title, '彩插');
  });

  test('identically named front matter continuations share one scope', () {
    final content = parse(
      frontMatterFiles({
        'summary': page('简介', '<p>First part.</p>'),
        'moreSummary': page('简介', '<p>Second part.</p>'),
        'a': page('A', '<p>Body.</p>'),
        'b': page('B', '<p>Next.</p>'),
      }),
    ).content;
    expect(content.navigation.map((e) => e.title), ['简介', 'First', 'Second']);
    final index = LocalChapterProgressIndex.build(
      metrics: content.progressMetrics,
      chapters: content.chapters,
      navigation: content.navigation,
    )!;
    expect(
      index.target(index.sections.first, 1).chapter,
      content.chapters[1].key,
    );
  });

  test('synthesis and navigation JSON retain readable content identities', () {
    final files = frontMatterFiles({
      'cover': page('Cover', picture),
      'summary': page('简介', '<p>Brief.</p>'),
      'a': page('A', '<p>Body.</p>'),
      'b': page('B', '<p>Next.</p>'),
    });
    final supplemented = parse(files).content;
    files['OPS/nav.xhtml'] = utf8.encode('<html/>');
    final fallback = parse(files).content;
    expect(supplemented.chapters, fallback.chapters);
    expect(supplemented.progressMetrics.order, fallback.progressMetrics.order);
    expect(
      supplemented.progressMetrics.revision,
      fallback.progressMetrics.revision,
    );
    expect(supplemented.progressMetrics.total, fallback.progressMetrics.total);
    final decoded = supplemented.navigation
        .map(
          (e) => LocalNavigationEntry.fromJson(
            jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>,
          ),
        )
        .toList();
    expect(
      decoded.map((e) => e.toJson()),
      supplemented.navigation.map((e) => e.toJson()),
    );
    expect(decoded[1].generatedLabel, isNull);
  });

  test(
    'generated title provenance survives JSON independently of spelling',
    () {
      final content = parse(
        frontMatterFiles({
          'cover': page('未知', picture, type: 'cover'),
          'title': page('标题', '<p>离线星空 1</p><p>测试作者</p>'),
          'a': page('A', '<p>Body.</p>'),
          'authored': page('Title page', '<p>Authored page.</p>'),
          'b': page('B', '<p>Next.</p>'),
        }),
      ).content;
      final entries = content.navigation
          .map(
            (e) => LocalNavigationEntry.fromJson(
              jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>,
            ),
          )
          .toList();
      expect(entries[0].generatedLabel, LocalNavigationLabel.cover);
      expect(entries[1].generatedLabel, LocalNavigationLabel.titlePage);
      expect(entries[3].title, entries[1].title);
      expect(entries[3].generatedLabel, isNull);
      final old = entries[1].toJson()..remove('generatedLabel');
      expect(LocalNavigationEntry.fromJson(old).generatedLabel, isNull);
      final future = entries[1].toJson()..['generatedLabel'] = 'futureLabel';
      expect(LocalNavigationEntry.fromJson(future).title, 'Title page');
      expect(LocalNavigationEntry.fromJson(future).generatedLabel, isNull);
    },
  );
}
