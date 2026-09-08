import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP43+DwHwAHAAK/K9fH4gAAAABJRU5ErkJggg==',
);

Map<String, List<int>> epubFiles({bool ncx = false, bool toc = true}) {
  final texts = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OPS/book.opf':
        '''<package xmlns="http://www.idpf.org/2007/opf" version="${ncx ? '2.0' : '3.0'}" unique-identifier="book">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book">self-authored</dc:identifier><dc:title>离线星空</dc:title><dc:creator>测试作者</dc:creator><dc:language>zh</dc:language><meta name="cover" content="cover"/></metadata>
      <manifest><item id="a" href="text/a.xhtml" media-type="application/xhtml+xml"/>
      <item id="b" href="text/b.xhtml" media-type="application/xhtml+xml"/>
      <item id="cover" href="images/星 空.png" media-type="image/png" properties="cover-image"/>
      ${!toc
            ? ''
            : ncx
            ? '<item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
            : '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'}
      </manifest><spine ${ncx && toc ? 'toc="toc"' : ''}><itemref idref="a"/><itemref idref="b"/></spine></package>''',
    'OPS/text/a.xhtml':
        '''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head><body>
      <h1 id="start">第一章 星海</h1><p id="one">一段<strong>强调</strong>，こんにちは。</p>
      <p id="two">第二段<br/>换行。</p><img src="../images/%E6%98%9F%20%E7%A9%BA.png" alt="星星"/>
      <hr/><p>结束。</p></body></html>''',
    'OPS/text/b.xhtml':
        '<html><body><h1 id="b">第二章</h1><p>独立的第二章正文。</p></body></html>',
    'OPS/nav.xhtml':
        '''<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol>
      <li><span>第二卷</span><ol><li><a href="text/b.xhtml#b">先列第二章</a></li></ol></li>
      <li><a href="text/a.xhtml#one">第一段</a><ol><li><a href="text/a.xhtml#two">第二段</a></li><li><a href="text/a.xhtml#missing">缺锚点</a></li></ol></li>
      </ol></nav></body></html>''',
    'OPS/toc.ncx': '''<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
      <navPoint id="v"><navLabel><text>第二卷</text></navLabel><content src="text/b.xhtml#b"/><navPoint id="b"><navLabel><text>第二章</text></navLabel><content src="text/b.xhtml#b"/></navPoint></navPoint>
      <navPoint id="a"><navLabel><text>第一段</text></navLabel><content src="text/a.xhtml#one"/><navPoint id="p"><navLabel><text>第二段</text></navLabel><content src="text/a.xhtml#two"/></navPoint><navPoint id="bad"><navLabel><text>缺锚点</text></navLabel><content src="text/a.xhtml#missing"/></navPoint></navPoint>
      </navMap></ncx>''',
  };
  return {
    for (final e in texts.entries) e.key: utf8.encode(e.value),
    'OPS/images/星 空.png': tinyPng,
  };
}

Uint8List zipFiles(Map<String, List<int>> files, {bool compress = true}) {
  final archive = Archive();
  for (final e in files.entries) {
    final file = ArchiveFile(e.key, e.value.length, e.value);
    if (!compress || e.key == 'mimetype') {
      file.compression = CompressionType.none;
    }
    archive.add(file);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
