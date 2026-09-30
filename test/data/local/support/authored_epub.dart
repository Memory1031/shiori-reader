import 'dart:convert';
import 'dart:typed_data';
import 'epub_fixtures.dart';

// Entirely self-authored text and a small geometric bitmap.
Uint8List authoredEpub() {
  final files = epubFiles();
  files['OPS/book.opf'] = utf8.encode(
    '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book">authored-fixture</dc:identifier><dc:title>Native Layout</dc:title></metadata>
    <manifest>
      <item id="a" href="text/a.xhtml" media-type="application/xhtml+xml"/>
      <item id="toc" href="text/toc.xhtml" media-type="application/xhtml+xml"/>
      <item id="logo" href="text/logo.xhtml" media-type="application/xhtml+xml"/>
      <item id="b" href="text/b.xhtml" media-type="application/xhtml+xml"/>
      <item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/>
      <item id="image" href="images/logo.png" media-type="image/png"/>
    </manifest><spine><itemref idref="a"/><itemref idref="toc"/><itemref idref="logo"/><itemref idref="b"/></spine>
    </package>''',
  );
  const css =
      'html,body{font-size:12px;margin:0} '
      '.panel{border-style:ridge groove none none;border-width:6px;border-color:#4682b4;padding:8px;margin:12px} '
      'h1{font-size:xxx-large;margin:.2em 0 .3em} '
      'h2{font-size:x-large;margin:.2em 0} '
      '.entry{text-align:center;margin:.3em 0} '
      '.label{background-color:#544f65;color:white;border-radius:30px;padding:.3em;font-weight:bold} '
      '.logo{margin-top:36%} '
      'dl{border-bottom-style:solid;border-width:.2em;margin:0 2% 0 32%;padding-right:6%;font-size:1.1em}';
  void page(String path, String body) {
    files[path] = utf8.encode(
      '<html><head><style>$css</style></head><body>$body</body></html>',
    );
  }

  page(
    'OPS/text/a.xhtml',
    '<div class="panel"><h1>Native <span style="color:#4682b4">Authored</span> Layout</h1>'
        '<h2>Synthetic edition</h2><p>Independent sample</p></div>',
  );
  page(
    'OPS/text/toc.xhtml',
    '<h2>Contents</h2><hr style="width:50%;margin-left:auto;margin-right:auto">'
        '${List.generate(7, (i) => '<p class="entry"><a href="${i == 0 ? '../notes.xhtml#note' : 'b.xhtml#target'}"><span class="label">Entry ${i + 1}</span></a></p><p><br/></p>').join()}',
  );
  page(
    'OPS/text/logo.xhtml',
    '<div class="logo"><img src="../images/logo.png" width="160" height="40" alt="Geometric sample"/></div>'
        '<dl><dt>Production</dt><dd>Synthetic studio</dd><dd>Open native flow</dd></dl>',
  );
  page(
    'OPS/text/b.xhtml',
    '<p id="target">SOURCE_START ${List.generate(100, (i) => 'Record ${i.toString().padLeft(3, '0')} native text. ').join()} SOURCE_END</p>'
        '<p>Before table</p><table><tr><td style="width:2em;border-right:1px solid black">A</td><td>Short row</td></tr></table><p>After table</p>',
  );
  page('OPS/notes.xhtml', '<p id="note">Auxiliary destination</p>');
  files['OPS/images/logo.png'] = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAKAAAAAoCAYAAAB5LPGYAAABB0lEQVR4nO3bwQ2DUBADUapLYakp/SUtLAjsWWWe9O8jrY9wfKWiox2g/+YAVeUAVeUAVeUAVeUAVeUAVTUe4Ov9efSd8XTL1a50G7lvygEuPTC9b8oBLj0wvW/KAS49ML1vygEuPTC9b+ryAJvuPEiqjYLW5QBDbRS0LgcYaqOgdTnAUBsFrcsBhtooaF0OMNRGQetygKE2ClqXAwy1UdC6HGCojYLW5QBDbRS0LgcYaqOgdTnAUBsFrcsBhtooaF0OMNRGQevyc6wbu9Jt5L4pB7j0wPS+KQe49MD0vikHuPTA9L4pB7j0wPS+KX9MV5UDVJUDVJUDVJUDVJUDVJUDVJUDVNUPniq8Fj6k/uAAAAAASUVORK5CYII=',
  );
  return zipFiles(files);
}
