import 'dart:convert';
import 'epub_fixtures.dart';

Map<String, List<int>> mixedEpub({
  String? body,
  String metadata = '',
  String properties = 'rendition:layout-pre-paginated',
  bool repeat = false,
}) {
  final files = epubFiles();
  files['OPS/book.opf'] = utf8.encode('''<package version="3.0">
<metadata>$metadata</metadata><manifest>
<item id="a" href="text/a.xhtml" media-type="application/xhtml+xml"/>
<item id="b" href="text/b.xhtml" media-type="application/xhtml+xml"/>
<item id="c" href="text/c.xhtml" media-type="application/xhtml+xml"/>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
</manifest><spine><itemref idref="a" properties="$properties"/>
<itemref idref="b" properties="page-spread-left"/>
<itemref idref="c" properties="rendition:layout-pre-paginated"/>
${repeat ? '<itemref idref="a" properties="rendition:layout-pre-paginated"/>' : ''}
</spine></package>''');
  files['OPS/text/a.xhtml'] = utf8.encode(
    '''<html><body>${body ?? '<div id="one"><svg xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="../images/星 空.png"/></svg></div>'}</body></html>''',
  );
  files['OPS/text/c.xhtml'] = utf8.encode(
    '<html><body><img src="../images/wide.png"/></body></html>',
  );
  // Synthetic, fully decodable 1000 x 100 raster image.
  files['OPS/images/wide.png'] = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAA+gAAABkCAIAAACaW42NAAACUUlEQVR4nO3OMQ3AMAADsEAvlEIZtEHImR6WDMA59wMAAB6X+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoMp8AAAAVJkPAACAKvMBAABQZT4AAACqzAcAAECV+QAAAKgyHwAAAFXmAwAAoPoBGGuW5WZecoYAAAAASUVORK5CYII=',
  );
  return files;
}
