import '../../html/prose_semantics.dart';
import '../../html/prose_ruby.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import '../../../domain/contracts/local_book_decoder.dart';
import '../../../domain/contracts/local_books.dart';
import '../../../domain/contracts/local_content_links.dart';
import '../../../domain/models/models.dart';
import '../txt/txt_decoder.dart';
import '../txt/txt_parser.dart' show filenameTitle;
import 'epub_zip.dart';
import 'epub_image_dimensions.dart';
import 'epub_presentation.dart';
import 'epub_svg_presentation.dart';
import 'epub_text_styles.dart';
import 'epub_rich_styles.dart';
import 'epub_image_candidates.dart';
import 'epub_diagnostics.dart';
import 'epub_footnotes.dart';
import 'epub_fixed_image.dart';

final class ParsedEpub {
  ParsedEpub(this.content, this.media, this.diagnostics);
  final EpubDiagnostics diagnostics;
  final LocalBookContent content;
  final Map<String, Uint8List> media;
}

/// Only package-local references are returned. External resources are never
/// resolved or fetched. Percent decoding happens once, before containment.
(String, String?)? epubReference(String base, String reference) {
  final uri = Uri.tryParse(
    reference.replaceAll(RegExp(r'^[ \t\r\n\f]+|[ \t\r\n\f]+$'), ''),
  );
  if (uri == null || uri.hasScheme || uri.hasAuthority) {
    return null;
  }
  final raw = Uri.decodeComponent(uri.path);
  if (raw.startsWith('/') ||
      raw.contains('\\') ||
      raw.contains('\x00') ||
      raw.split('/').first.contains(':')) {
    invalidZip();
  }
  final parts = raw.isEmpty
      ? base.split('/')
      : [...base.split('/')..removeLast(), ...raw.split('/')];
  final normalized = <String>[];
  for (final part in parts) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..') {
      if (normalized.isEmpty) invalidZip();
      normalized.removeLast();
    } else {
      normalized.add(part);
    }
  }
  if (normalized.isEmpty) invalidZip();
  if (normalized.first.contains(':')) invalidZip();
  return (
    normalized.join('/'),
    uri.hasFragment ? Uri.decodeComponent(uri.fragment) : null,
  );
}

/// Optional styles may be malformed; never reinterpret an escaping path as
/// package-local. Structural and content references still use epubReference.
String? optionalEpubStyleReference(String base, String reference) {
  try {
    return epubReference(base, reference)?.$1;
  } on LocalParseException catch (error) {
    if (error.problem != LocalParseProblem.invalid) rethrow;
    return null;
  } on FormatException {
    // Invalid percent encoding is also an unusable optional reference.
    return null;
  }
}

Iterable<XmlElement> elements(XmlNode node, String name) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
String? attr(XmlElement e, String name) {
  for (final a in e.attributes) {
    if (a.name.local == name && a.name.prefix == null) return a.value;
  }
  return null;
}

Iterable<XmlElement> packageChildren(XmlElement node, String name) =>
    node.childElements.where(
      (e) =>
          e.name.local == name && e.name.namespaceUri == node.name.namespaceUri,
    );

bool isToc(dom.Element node) {
  for (final entry in node.attributes.entries) {
    final name = entry.key.toString();
    final parts = name.split(':');
    if (parts.length != 2 || parts.last != 'type') continue;
    String? namespace;
    for (
      dom.Element? ancestor = node;
      ancestor != null;
      ancestor = ancestor.parent
    ) {
      namespace = ancestor.attributes['xmlns:${parts.first}'];
      if (namespace != null) break;
    }
    if ((namespace == 'http://www.idpf.org/2007/ops' ||
            namespace == null && parts.first == 'epub') &&
        entry.value.split(RegExp(r'\s+')).contains('toc')) {
      return true;
    }
  }
  return (node.attributes['type'] ?? '').split(RegExp(r'\s+')).contains('toc');
}

class EpubParser {
  EpubParser(
    this.bytes,
    this.book,
    this.filename, {
    this.includePresentations = false,
  });
  final bool includePresentations;
  final Uint8List bytes;
  final NovelKey book;
  final String filename;
  late final zip = EpubZip(bytes);
  final _diagnostics = EpubDiagnosticCollector();
  final media = <String, Uint8List>{};
  final mediaByPath = <String, MediaRef>{};
  final imageSizes = <MediaRef, ({int width, int height})?>{};
  final items = <String, _Item>{};
  final chapters = <ChapterContent>[];
  final auxiliary = <ChapterContent>[];
  final primary = <ChapterKey>[];
  final _fixedChapters = <ChapterKey>{};
  final chapterPaths = <ChapterKey, String>{};
  final requestedPaths = <String>[];
  final rawLinks =
      <
        String,
        List<(int, String, String?, String?, LocalLinkUnavailable?, int?, int?)>
      >{};
  var linkCount = 0;
  final _linkRegions = <String, Map<int, LocalLinkRegion>>{};
  final _footnotes =
      <String, List<(int, String, String?, LocalLinkUnavailable?)>>{};
  final _noteDocuments = <String, Map<String, dom.Element>?>{};
  var _noteChars = 0;
  final presentations = <String, String>{};
  final byPath = <String, ChapterContent>{};
  final skippedEmptyPaths = <String>{};
  final fragments = <String, Map<String, (String, int)>>{};
  int mediaSize = 0, textSize = 0;

  String text(String path, {int limit = 4 * 1024 * 1024}) {
    final b = zip.read(path, limit: limit);
    final encoding = txtBom(b) ?? TxtEncoding.utf8;
    return decodeTxt(b, encoding);
  }

  XmlDocument xml(String path) {
    final input = text(path);
    // XML parser never receives DTD/entity declarations; no external resolver.
    if (RegExp(
      r'<!\s*ENTITY|<!\s*DOCTYPE[^>]*\[',
      caseSensitive: false,
    ).hasMatch(input)) {
      invalidZip();
    }
    final document = XmlDocument.parse(
      input.replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), ''),
    );
    var count = 0;
    final stack = <(XmlNode, int)>[(document, 0)];
    while (stack.isNotEmpty) {
      final (node, depth) = stack.removeLast();
      if (++count > 100000 || depth > 128) zipLimit();
      stack.addAll(node.children.map((child) => (child, depth + 1)));
    }
    return document;
  }

  String requiredPath(String base, String href) =>
      epubReference(base, href)?.$1 ?? (invalidZip());

  MediaRef? image(String path) {
    if (mediaByPath.containsKey(path)) return mediaByPath[path];
    if (!zip.entries.containsKey(path)) {
      _diagnostics.add(EpubDiagnosticCode.missingImage);
      return null;
    }
    final b = zip.read(path);
    // Native raster decoder supports these formats; SVG is deliberately not
    // passed to a browser, and a missing/unsupported image stays a local gap.
    if (epubRasterMime(b) == null) {
      _diagnostics.add(EpubDiagnosticCode.unsupportedImage);
      return null;
    }
    final hash = sha256.convert(b).toString();
    if (!media.containsKey(hash)) {
      mediaSize += b.length;
      if (mediaSize > 128 * 1024 * 1024) zipLimit();
      media[hash] = b;
    }
    final ref = mediaByPath[path] = MediaRef(
      sourceId: book.sourceId,
      mediaId: '${book.novelId}/$hash',
    );
    imageSizes.putIfAbsent(ref, () => epubImageDimensions(b));
    return ref;
  }

  ParsedEpub parse() {
    if (utf8.decode(zip.read('mimetype', limit: 100)).trim() !=
        'application/epub+zip') {
      invalidZip();
    }
    // Some otherwise readable packages compress mimetype or add a newline.
    // EpubZip still verifies compression, declared length and CRC.
    if (zip.entries.containsKey('META-INF/encryption.xml')) {
      // Font obfuscation is safe to ignore because publisher fonts are unused.
      final encryption = xml('META-INF/encryption.xml');
      for (final encrypted in elements(encryption, 'EncryptedData')) {
        final methods = elements(encrypted, 'EncryptionMethod');
        final refs = elements(encrypted, 'CipherReference');
        if (methods.length != 1 ||
            refs.length != 1 ||
            !{
              'http://www.idpf.org/2008/embedding',
              'http://ns.adobe.com/pdf/enc#RC',
            }.contains(attr(methods.single, 'Algorithm')) ||
            !RegExp(
              r'\.(?:otf|ttf|woff2?)$',
              caseSensitive: false,
            ).hasMatch(attr(refs.single, 'URI') ?? '')) {
          throw const LocalParseException(LocalParseProblem.drm);
        }
      }
    }
    final container = xml('META-INF/container.xml');
    final root = container.rootElement;
    if (root.name.local != 'container' ||
        root.name.namespaceUri != null &&
            root.name.namespaceUri !=
                'urn:oasis:names:tc:opendocument:xmlns:container') {
      invalidZip();
    }
    final roots = packageChildren(root, 'rootfiles')
        .expand((node) => packageChildren(node, 'rootfile'))
        .where((e) => attr(e, 'media-type') == 'application/oebps-package+xml');
    if (roots.isEmpty) invalidZip();
    final opfPath = requiredPath('', attr(roots.first, 'full-path') ?? '');
    final opf = xml(opfPath);
    if (opf.rootElement.name.local != 'package' ||
        opf.rootElement.name.namespaceUri != null &&
            opf.rootElement.name.namespaceUri !=
                'http://www.idpf.org/2007/opf') {
      invalidZip();
    }
    final package = opf.rootElement;
    final manifests = packageChildren(package, 'manifest').toList();
    final spines = packageChildren(package, 'spine').toList();
    final metadataNodes = packageChildren(package, 'metadata').toList();
    if (manifests.length != 1 ||
        spines.length != 1 ||
        metadataNodes.length > 1) {
      invalidZip();
    }
    final metadata = metadataNodes.firstOrNull;
    Iterable<XmlElement> metadataElements(String name) =>
        metadata?.childElements.where(
          (e) =>
              e.name.local == name &&
              (e.name.namespaceUri ==
                      (name == 'meta'
                          ? package.name.namespaceUri
                          : 'http://purl.org/dc/elements/1.1/') ||
                  e.name.namespaceUri == null),
        ) ??
        const <XmlElement>[];
    for (final meta in metadataElements('meta')) {
      if (attr(meta, 'property') == 'rendition:layout' &&
              meta.innerText.trim() == 'pre-paginated' ||
          attr(meta, 'name') == 'fixed-layout' &&
              attr(meta, 'content') == 'true') {
        throw const LocalParseException(LocalParseProblem.fixedLayout);
      }
    }
    for (final e in packageChildren(manifests.single, 'item')) {
      final id = attr(e, 'id'), href = attr(e, 'href');
      if (id == null ||
          id.trim().isEmpty ||
          href == null ||
          href.trim().isEmpty ||
          items.containsKey(id)) {
        invalidZip();
      }
      final path = epubReference(opfPath, href)?.$1;
      items[id] = _Item(
        path,
        attr(e, 'media-type') ?? '',
        (attr(e, 'properties') ?? '').split(RegExp(r'\s+')).toSet(),
        attr(e, 'fallback'),
      );
    }
    final spine = spines.single;
    final occurrences = <String, int>{};
    var spineCount = 0;
    var repeatedBlocks = 0;
    final epub3 = attr(package, 'version') == '3.0';

    for (final ref in packageChildren(spine, 'itemref')) {
      final fixed = (attr(ref, 'properties') ?? '')
          .split(RegExp(r'\s+'))
          .contains('rendition:layout-pre-paginated');
      final chain = <_Item>{};
      var item = items[attr(ref, 'idref')];
      while (item != null &&
          !{'application/xhtml+xml', 'text/html'}.contains(item.type)) {
        if (chain.contains(item)) invalidZip();
        chain.add(item);
        item = items[item.fallback];
      }
      if (item == null ||
          item.path == null ||
          !{'application/xhtml+xml', 'text/html'}.contains(item.type)) {
        invalidZip();
      }
      final path = item.path!;
      final occurrence = occurrences.update(
        path,
        (n) => n + 1,
        ifAbsent: () => 0,
      );
      if (++spineCount > 10000) zipLimit();
      if (occurrence > 0 && !epub3) invalidZip();
      if (chain.isNotEmpty) _diagnostics.add(EpubDiagnosticCode.spineFallback);
      if (fixed) {
        _fixedImageChapter(path, occurrence);
      } else if (occurrence == 0) {
        _chapter(path);
      } else if (byPath[path] case final original?) {
        repeatedBlocks += original.blocks.length;
        if (repeatedBlocks > 100000) zipLimit();
        final key = LocalBookIdentity.epubOccurrence(book, path, occurrence);
        chapterPaths[key] = path;
        chapters.add(
          ChapterContent(
            key: key,
            title: original.title,
            blocks: original.blocks,
          ),
        );
        if (presentations[original.key.chapterId] case final html?) {
          presentations[key.chapterId] = html;
        }
      }
      final current = LocalBookIdentity.epubOccurrence(book, path, occurrence);
      if (chapterPaths.containsKey(current) && attr(ref, 'linear') != 'no') {
        primary.add(current);
      }
      for (final alias in chain) {
        if (alias.path != null && byPath[item.path] != null) {
          byPath[alias.path!] = byPath[item.path]!;
          fragments[alias.path!] = fragments[item.path]!;
        }
      }
    }
    if (chapters.isEmpty) invalidZip();
    final manifestText = items.values
        .where(
          (i) =>
              i.path != null &&
              {'application/xhtml+xml', 'text/html'}.contains(i.type),
        )
        .map((i) => i.path!)
        .toSet();
    final attempted = <String>{};
    var auxiliaryAttempts = 0;
    for (var i = 0; i < requestedPaths.length; i++) {
      final path = requestedPaths[i];
      if (byPath.containsKey(path) ||
          skippedEmptyPaths.contains(path) ||
          !attempted.add(path) ||
          !manifestText.contains(path) ||
          !zip.entries.containsKey(path)) {
        continue;
      }
      if (++auxiliaryAttempts > 64) zipLimit();
      final before = chapters.length;
      try {
        _chapter(path);
      } on LocalParseException catch (error) {
        if (error.problem != LocalParseProblem.invalid) rethrow;
        _diagnostics.add(EpubDiagnosticCode.unusableLinkTarget);
      }
      if (chapters.length > before) auxiliary.add(chapters.removeLast());
    }
    final links = <LocalContentLink>[];
    for (final source in [...chapters, ...auxiliary]) {
      if (_fixedChapters.contains(source.key)) continue;
      final path = chapterPaths[source.key]!;
      for (final note
          in _footnotes[path] ??
              <(int, String, String?, LocalLinkUnavailable?)>[]) {
        if (note.$1 >= source.blocks.length) continue;
        final sourceBlock = source.blocks[note.$1];
        final text = switch (sourceBlock) {
          ParagraphBlock(:final text) || HeadingBlock(:final text) => text,
          _ => '',
        };
        final offset = text.indexOf(note.$2);
        if (offset < 0) continue;
        links.add(
          LocalContentLink(
            source: source.key,
            sourceBlockKey: sourceBlock.blockKey,
            label: note.$2,
            sourceOffset: text.substring(0, offset).runes.length,
            footnoteText: note.$3,
            target: note.$4 == null ? source.key : null,
            unavailable: note.$4,
          ),
        );
        if (links.length > 10000) zipLimit();
      }
      var rawIndex = -1;
      for (final raw
          in rawLinks[path] ??
              <
                (
                  int,
                  String,
                  String?,
                  String?,
                  LocalLinkUnavailable?,
                  int?,
                  int?,
                )
              >[]) {
        rawIndex++;
        if (raw.$1 >= source.blocks.length) continue;
        var unavailable = raw.$5;
        final destination = raw.$3 == path ? source : byPath[raw.$3];
        (String, int)? anchor;
        if (unavailable == null) {
          if (destination == null) {
            unavailable = manifestText.contains(raw.$3)
                ? LocalLinkUnavailable.missingDocument
                : LocalLinkUnavailable.unsupported;
          } else if (raw.$4?.isNotEmpty == true) {
            anchor = fragments[raw.$3]?[raw.$4];
            if (anchor == null) {
              unavailable = LocalLinkUnavailable.missingAnchor;
            }
          }
        }
        if (unavailable != null) {
          _diagnostics.add(EpubDiagnosticCode.unusableLinkTarget);
        }
        links.add(
          LocalContentLink(
            source: source.key,
            sourceBlockKey: source.blocks[raw.$1].blockKey,
            label: raw.$2,
            region: _linkRegions[path]?[rawIndex],
            sourceOffset: raw.$6,
            sourceLength: raw.$7,
            target: unavailable == null ? destination?.key : null,
            targetBlockKey: unavailable == null ? anchor?.$1 : null,
            targetOffset: unavailable == null ? anchor?.$2 : null,
            unavailable: unavailable,
          ),
        );
        if (links.length > 10000) zipLimit();
      }
    }
    final navItem = items.values
        .where((e) => e.properties.contains('nav'))
        .firstOrNull;
    var navigation = <LocalNavigationEntry>[];
    if (navItem?.path case final path? when zip.entries.containsKey(path)) {
      final doc = _html(path);
      final toc = doc.querySelectorAll('nav').where(isToc).firstOrNull;
      final list = toc?.querySelector('ol');
      if (list != null) navigation = _nav(list, path, 0);
      if (navigation.isEmpty) {
        _diagnostics.add(EpubDiagnosticCode.unusableNavigation);
      }
    } else if (navItem != null) {
      _diagnostics.add(EpubDiagnosticCode.missingNavigation);
    }
    if (navigation.isEmpty) {
      final ncx =
          items[attr(spine, 'toc')] ??
          items.values
              .where((e) => e.type == 'application/x-dtbncx+xml')
              .firstOrNull;
      if (ncx?.path case final path? when zip.entries.containsKey(path)) {
        XmlElement? ncxRoot;
        try {
          ncxRoot = xml(path).rootElement;
        } on XmlException {
          // A malformed optional TOC must not discard valid spine content.
          // ZIP integrity, entity and budget errors deliberately propagate.
        }
        if (ncxRoot != null &&
            ncxRoot.name.local == 'ncx' &&
            (ncxRoot.name.namespaceUri == null ||
                ncxRoot.name.namespaceUri ==
                    'http://www.daisy.org/z3986/2005/ncx/')) {
          final map = packageChildren(ncxRoot, 'navMap').firstOrNull;
          if (map != null) navigation = _ncx(map, path, 0);
        }
        if (navigation.isEmpty) {
          _diagnostics.add(EpubDiagnosticCode.unusableNavigation);
        }
      } else if (ncx != null) {
        _diagnostics.add(EpubDiagnosticCode.missingNavigation);
      }
    }
    if (navigation.isEmpty) {
      _diagnostics.add(EpubDiagnosticCode.syntheticNavigation);
      navigation = [
        for (final c in chapters)
          LocalNavigationEntry(title: c.title, chapterKey: c.key),
      ];
    }
    MediaRef? cover;
    final coverMeta = metadataElements(
      'meta',
    ).where((e) => attr(e, 'name') == 'cover').firstOrNull;
    final candidates = <_Item>[
      ...items.values.where((e) => e.properties.contains('cover-image')),
      ?items[coverMeta == null ? null : attr(coverMeta, 'content')],
    ];
    for (final item in candidates) {
      if (item.path != null) cover = image(item.path!);
      if (cover != null) break;
    }
    if (cover == null) {
      final guide = packageChildren(package, 'guide').firstOrNull;
      final reference = guide == null
          ? null
          : packageChildren(guide, 'reference')
                .where(
                  (e) => (attr(e, 'type') ?? '')
                      .split(RegExp(r'\s+'))
                      .contains('cover'),
                )
                .firstOrNull;
      final path = reference == null
          ? null
          : epubReference(opfPath, attr(reference, 'href') ?? '')?.$1;
      if (path != null && zip.entries.containsKey(path)) {
        final item = items.values.where((e) => e.path == path).firstOrNull;
        if (item != null &&
            {'application/xhtml+xml', 'text/html'}.contains(item.type)) {
          final document = _html(path);
          for (final node in document.querySelectorAll('img, image')) {
            for (final href in epubImageCandidates(node).take(128)) {
              final imagePath = epubReference(path, href)?.$1;
              if (imagePath != null) cover = image(imagePath);
              if (cover != null) break;
            }
            if (cover != null) break;
          }
        } else {
          cover = image(path);
        }
      }
    }
    final titles = metadataElements(
      'title',
    ).map((e) => _labelWhitespace(e.innerText)).where((e) => e.isNotEmpty);
    final content = LocalBookContent(
      auxiliaryChapters: auxiliary,
      links: links,
      readingOrder: primary,
      detail: NovelDetail(
        summary: NovelSummary(
          key: book,
          title: titles.firstOrNull ?? filenameTitle(filename),
          cover: cover,
          authors: metadataElements('creator')
              .map((e) => _labelWhitespace(e.innerText))
              .where((e) => e.isNotEmpty),
        ),
        synopsis: metadataElements('description').firstOrNull?.innerText ?? '',
      ),
      catalog: Catalog(
        novelKey: book,
        volumes: [
          Volume(
            groupId: 'epub',
            isSynthetic: true,
            chapters: [
              for (var i = 0; i < chapters.length; i++)
                Chapter(
                  key: chapters[i].key,
                  title: chapters[i].title,
                  ordinal: i,
                  volumeGroupId: 'epub',
                ),
            ],
          ),
        ],
      ),
      chapters: chapters,
      navigation: navigation,
    );
    return ParsedEpub(content, media, _diagnostics.snapshot());
  }

  dom.Document _html(String path) {
    final input = text(path);
    textSize += input.length;
    if (textSize > 12 * 1024 * 1024) zipLimit();
    if (RegExp(r'<!\s*ENTITY', caseSensitive: false).hasMatch(input)) {
      invalidZip();
    }
    // XHTML permits self-closing script/style elements; HTML's raw-text parser
    // otherwise swallows the rest of the document as script. Never execute it.
    final document = html.parse(
      input.replaceAll(
        RegExp(
          r'''<(?:script|style)\b(?:[^>"']|"[^"]*"|'[^']*')*/\s*>''',
          caseSensitive: false,
        ),
        '',
      ),
    );
    // Bound traversal and nesting before recursive rendering.
    var count = 0;
    final stack = <(dom.Node, int)>[(document, 0)];
    while (stack.isNotEmpty) {
      final (node, depth) = stack.removeLast();
      if (++count > 100000 || depth > 128) zipLimit();
      stack.addAll(node.nodes.map((n) => (n, depth + 1)));
    }
    return document;
  }

  void _fixedImageChapter(String path, int occurrence) {
    final doc = _html(path);
    final node = epubFixedImage(
      doc,
      epubDocumentStylesheets(
        doc,
        path,
        optionalEpubStyleReference,
        (p) => zip.entries.containsKey(p) ? text(p) : '',
      ).map((sheet) => sheet.$2),
    );
    MediaRef? media;
    for (final href in epubImageCandidates(node).take(128)) {
      final ref = epubReference(path, href);
      if (ref != null) media = image(ref.$1);
      if (media != null) break;
    }
    if (media == null) {
      throw const LocalParseException(LocalParseProblem.fixedLayout);
    }
    final size = imageSizes[media];
    final title = doc.querySelector('title')?.text.trim();
    final chapter = ChapterContent(
      key: LocalBookIdentity.epubOccurrence(book, path, occurrence),
      title: title?.isNotEmpty == true ? title! : filenameTitle(path),
      blocks: [
        ImageBlock(
          media: media,
          alt: node.attributes['alt'],
          width: size?.width,
          height: size?.height,
        ),
      ],
    );
    _fixedChapters.add(chapter.key);
    chapters.add(chapter);
    chapterPaths[chapter.key] = path;
    if (!byPath.containsKey(path)) {
      byPath[path] = chapter;
      // Only the image and its containers are navigable anchors. Discarded
      // hotspot geometry must not create prose links or auxiliary chapters.
      final anchors = <String, (String, int)>{};
      for (dom.Element? e = node; e != null; e = e.parent) {
        if (e.id.isNotEmpty) {
          anchors.putIfAbsent(e.id, () => (chapter.blocks.single.blockKey, 0));
        }
      }
      fragments[path] = anchors;
    }
  }

  void _chapter(String path) {
    final doc = _html(path);
    var noteNumber = 0;
    final noteTargets = epubNoteTargets(doc);
    final authoredMarkers = RegExp(r'⁽[⁰¹²³⁴⁵⁶⁷⁸⁹]+⁾')
        .allMatches(doc.documentElement?.text ?? '')
        .map((match) => match.group(0)!)
        .toSet();
    final styles = epubTextStyles(
      doc,
      epubDocumentStylesheets(
        doc,
        path,
        optionalEpubStyleReference,
        (p) => zip.entries.containsKey(p) ? text(p) : '',
      ).map((sheet) => sheet.$2),
    );
    final richStyles = epubRichStyles(doc, styles);
    var activeStyle = const EpubRichStyle();
    BlockBox? activeBox;
    var boxGroup = 0;
    final styleSpans = <(EpubRichStyle, int, int)>[];
    dom.Element? paragraphOwner;
    String? property(String name) {
      for (var node = paragraphOwner; node != null; node = node.parent) {
        if (styles[node]?[name] case final value?) return value;
      }
      return null;
    }

    final svgHotspots = <EpubSvgHotspot>[];
    final presentation = includePresentations
        ? epubPresentation(
            doc,
            path,
            (p) => zip.entries.containsKey(p) ? text(p) : '',
            (p) => zip.entries.containsKey(p)
                ? zip.read(p, limit: 8 * 1024 * 1024)
                : Uint8List(0),
            (base, href) => epubReference(base, href)?.$1,
            resolveStyle: optionalEpubStyleReference,
            onSvgHotspot: svgHotspots.add,
          )
        : null;
    if (presentation != null) {
      presentations[LocalBookIdentity.chapter(book, 'epub:$path').chapterId] =
          presentation;
    }

    final blocks = <ContentBlock>[];
    final anchors = <String, (int, int)>{};
    final pendingAnchors = <String>[];
    int? activeLink;
    final spans = <(int, int, int)>[];
    final inlineImages = <InlineImage>[];
    final rubyRanges = ProseRubyRanges();
    var explicitGapEm = 0.0;
    final buffer = ProseTextBuffer(
      onWrite: (start, end) {
        if (!activeStyle.isDefault) {
          if (styleSpans.isNotEmpty &&
              identical(styleSpans.last.$1, activeStyle) &&
              styleSpans.last.$3 == start) {
            final last = styleSpans.removeLast();
            styleSpans.add((activeStyle, last.$2, end));
          } else {
            styleSpans.add((activeStyle, start, end));
          }
        }
        final link = activeLink;
        if (link == null) return;
        if (spans.isNotEmpty &&
            spans.last.$1 == link &&
            spans.last.$3 == start) {
          final last = spans.removeLast();
          spans.add((link, last.$2, end));
        } else {
          spans.add((link, start, end));
        }
      },
    );
    var whitespace = ProseWhiteSpace.normal;
    var visible = true;
    void flush({int? heading}) {
      // HTML source indentation is collapsible whitespace, not first-line
      // indentation. Preserve authored NBSP / ideographic spaces and pre text.
      final rawText = buffer.rawText;
      final value = buffer.take();
      final trimStart = rawText.indexOf(value);
      final ruby = rubyRanges.take(rawText, value);
      // Normalize against the emitted block, then convert UTF-16 to code points.
      for (final id in pendingAnchors) {
        final anchor = anchors[id]!;
        final offset = (anchor.$2 - trimStart).clamp(0, value.length);
        anchors[id] = (anchor.$1, value.substring(0, offset).runes.length);
      }
      pendingAnchors.clear();
      for (final span in spans) {
        final start = (span.$2 - trimStart).clamp(0, value.length);
        final end = (span.$3 - trimStart).clamp(0, value.length);
        if (end <= start || value.substring(start, end).trim().isEmpty) {
          continue;
        }
        final records = rawLinks[path]!;
        final original = records[span.$1];
        final range = (
          blocks.length,
          original.$2,
          original.$3,
          original.$4,
          original.$5,
          value.substring(0, start).runes.length,
          value.substring(start, end).runes.length,
        );
        if (original.$6 == null) {
          records[span.$1] = range;
        } else {
          records.add(range);
          if (++linkCount > 10000) zipLimit();
        }
      }
      final images = inlineImages
          .map(
            (image) => InlineImage(
              offset:
                  image.offset -
                  rawText
                      .substring(0, trimStart.clamp(0, rawText.length))
                      .runes
                      .length,
              media: image.media,
              widthEm: image.widthEm,
              heightEm: image.heightEm,
              alt: image.alt,
            ),
          )
          .toList();
      final textStyles = <InlineTextStyle>[];
      for (final span in styleSpans) {
        final start = (span.$2 - trimStart).clamp(0, value.length);
        final end = (span.$3 - trimStart).clamp(0, value.length);
        if (end > start) {
          textStyles.add(
            span.$1.range(
              value.substring(0, start).runes.length,
              value.substring(start, end).runes.length,
              preserveNeutral: activeBox?.backgroundColor != null,
            ),
          );
        }
      }
      textStyles.removeWhere((s) => s.isNoOp);
      styleSpans.clear();
      inlineImages.clear();
      spans.clear();
      final gap = explicitGapEm;
      explicitGapEm = 0;
      if (value.trim().isEmpty) {
        if (activeBox != null && gap > 0) {
          blocks.add(
            ParagraphBlock(
              text: '',
              box: activeBox,
              authoredGapEm: gap.clamp(0, 16),
            ),
          );
          if (blocks.length > 100000) invalidZip();
        }
        return;
      }
      blocks.add(
        heading == null
            ? ParagraphBlock(
                inlineImages: images,
                inlineRuby: ruby,
                inlineStyles: textStyles,
                box: activeBox,
                text: value,
                alignment: switch (property('text-align')) {
                  'center' => ParagraphAlignment.center,
                  'right' => ParagraphAlignment.end,
                  _ => ParagraphAlignment.start,
                },
                leadingIndent: (() {
                  final indent = property('text-indent');
                  if (indent == null || !indent.endsWith('em')) return 0;
                  return (double.tryParse(
                            indent.substring(0, indent.length - 2),
                          ) ??
                          0)
                      .round()
                      .clamp(0, 8);
                })(),
              )
            : HeadingBlock(
                inlineImages: images,
                inlineRuby: ruby,
                inlineStyles: textStyles,
                box: activeBox,
                text: value,
                level: heading,
                alignment: switch (property('text-align')) {
                  'center' => ParagraphAlignment.center,
                  'right' => ParagraphAlignment.end,
                  _ => ParagraphAlignment.start,
                },
              ),
      );
      if (blocks.length > 100000) zipLimit();
    }

    const containers = {
      'body',
      'div',
      'section',
      'article',
      'main',
      'header',
      'footer',
      'aside',
      'blockquote',
      'ul',
      'ol',
      'figure',
    };
    const paragraphs = {'p', 'li', 'dt', 'dd', 'pre', 'figcaption', 'tr'};
    String? rubyAnnotation(dom.Element rt, bool inheritedVisible) {
      if (rt.attributes.containsKey('hidden') ||
          styles[rt]?['display'] == 'none') {
        return null;
      }
      final annotationVisible = switch (styles[rt]?['visibility']) {
        'visible' || 'initial' => true,
        'hidden' || 'collapse' => false,
        _ => inheritedVisible,
      };
      final text = StringBuffer();
      void collect(dom.Node node, bool visible) {
        if (node is dom.Text) {
          if (visible) text.write(node.text);
          return;
        }
        if (node is! dom.Element ||
            node.attributes.containsKey('hidden') ||
            styles[node]?['display'] == 'none') {
          return;
        }
        final childVisible = switch (styles[node]?['visibility']) {
          'visible' || 'initial' => true,
          'hidden' || 'collapse' => false,
          _ => visible,
        };
        for (final child in node.nodes) {
          collect(child, childVisible);
        }
      }

      for (final child in rt.nodes) {
        collect(child, annotationVisible);
      }
      return text.toString().replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ').trim();
    }

    late void Function(dom.Node) walk;
    void visit(dom.Node node) {
      if (node is dom.Text) {
        activeStyle = richStyles[node.parent] ?? const EpubRichStyle();
        if (visible) buffer.text(node.text, whitespace);
        return;
      }
      if (node is! dom.Element) return;
      activeStyle = richStyles[node] ?? const EpubRichStyle();
      final tag = node.localName ?? '';
      if (epubFootnote(node)) return;
      if ({
            'script',
            'style',
            'noscript',
            'iframe',
            'object',
            'embed',
            'head',
            'audio',
            'video',
            'canvas',
          }.contains(tag) ||
          node.attributes.containsKey('hidden') ||
          styles[node]?['display'] == 'none') {
        return;
      }
      final heading = proseHeadingLevel(tag);
      final boundary =
          tag == 'hr' ||
          containers.contains(tag) ||
          paragraphs.contains(tag) ||
          heading != null;
      if (boundary) flush();
      final previousWhitespace = whitespace;
      final previousVisible = visible;
      whitespace = proseWhiteSpace(
        styles[node]?['white-space'],
        tag == 'pre' ? ProseWhiteSpace.pre : whitespace,
      );
      visible = switch (styles[node]?['visibility']) {
        'visible' || 'initial' => true,
        'hidden' || 'collapse' => false,
        _ => visible,
      };
      if (!visible && {'img', 'image', 'hr', 'br', 'rp'}.contains(tag)) {
        whitespace = previousWhitespace;
        visible = previousVisible;
        return;
      }
      final previousOwner = paragraphOwner;
      final previousLink = activeLink;
      if (paragraphs.contains(tag) ||
          containers.contains(tag) ||
          heading != null) {
        paragraphOwner = node;
      }
      final id = node.id.isNotEmpty ? node.id : node.attributes['name'];
      if (id != null && id.isNotEmpty && visible) {
        if (!anchors.containsKey(id)) {
          anchors[id] = (blocks.length, buffer.length);
          pendingAnchors.add(id);
        }
      }
      if (tag == 'a' &&
          visible &&
          node.attributes.containsKey('href') &&
          !(presentation != null &&
              node.namespaceUri == 'http://www.w3.org/2000/svg')) {
        if (++linkCount > 10000) zipLimit();
        (String, String?)? ref;
        LocalLinkUnavailable? unavailable;
        try {
          ref = epubReference(path, node.attributes['href']!);
          if (ref == null) unavailable = LocalLinkUnavailable.external;
        } on FormatException {
          unavailable = LocalLinkUnavailable.unsupported;
        }
        if (epubNoteref(node)) {
          String? noteText;
          if (ref != null) {
            Map<String, dom.Element>? target;
            if (ref.$1 == path) {
              target = noteTargets;
            } else if (items.values.any(
                  (item) =>
                      item.path == ref!.$1 &&
                      {
                        'application/xhtml+xml',
                        'text/html',
                      }.contains(item.type),
                ) &&
                zip.entries.containsKey(ref.$1)) {
              if (!_noteDocuments.containsKey(ref.$1)) {
                if (_noteDocuments.length >= 64) zipLimit();
                try {
                  _noteDocuments[ref.$1] = epubNoteTargets(_html(ref.$1));
                } on LocalParseException catch (error) {
                  if (error.problem != LocalParseProblem.invalid) rethrow;
                  _noteDocuments[ref.$1] = null;
                }
              }
              target = _noteDocuments[ref.$1];
            }
            final element = ref.$2 == null ? null : target?[ref.$2];
            if (target == null) {
              unavailable = LocalLinkUnavailable.missingDocument;
            } else if (element == null) {
              unavailable = LocalLinkUnavailable.missingAnchor;
            } else if (!epubFootnote(element)) {
              unavailable = LocalLinkUnavailable.unsupported;
            } else {
              noteText = epubFootnoteText(element);
              if (noteText == null) {
                unavailable = LocalLinkUnavailable.unsupported;
              }
            }
          }
          String marker;
          do {
            if (++noteNumber > 10000) zipLimit();
            marker = epubFootnoteMarker(noteNumber);
          } while (authoredMarkers.contains(marker));
          _noteChars += noteText?.length ?? 0;
          if (_noteChars > 1024 * 1024) zipLimit();
          (_footnotes[path] ??= []).add((
            blocks.length,
            marker,
            noteText,
            unavailable,
          ));
          buffer.write(marker);
          whitespace = previousWhitespace;
          visible = previousVisible;
          paragraphOwner = previousOwner;
          return;
        }
        final label = node.text.trim();
        activeLink = (rawLinks[path] ??= []).length;
        (rawLinks[path] ??= []).add((
          blocks.length,
          label.isEmpty ? '↗' : String.fromCharCodes(label.runes.take(200)),
          ref?.$1,
          ref?.$2,
          unavailable,
          null,
          null,
        ));
        if (ref != null) requestedPaths.add(ref.$1);
      }
      if (tag == 'img' || tag == 'image') {
        whitespace = previousWhitespace;
        visible = previousVisible;
        MediaRef? img;
        for (final href in epubImageCandidates(node).take(128)) {
          final ref = epubReference(path, href);
          if (ref != null) img = image(ref.$1);
          if (img != null) break;
        }
        if (img != null &&
            tag == 'img' &&
            paragraphOwner != null &&
            !{
              'block',
              'none',
              'flex',
              'grid',
            }.contains(styles[node]?['display'])) {
          double? em(String? value) {
            if (value == null || !RegExp(r'^\d*\.?\d+em$').hasMatch(value)) {
              return null;
            }
            return double.tryParse(value.substring(0, value.length - 2));
          }

          final size = imageSizes[img];
          final authoredHeight = em(styles[node]?['height']);
          final authoredWidth = em(styles[node]?['width']);
          if (size != null &&
              (authoredHeight != null || authoredWidth != null)) {
            final h =
                authoredHeight ?? authoredWidth! * size.height / size.width;
            final w = authoredWidth ?? h * size.width / size.height;
            if (h > 0 && h <= 4 && w > 0 && w <= 8) {
              buffer.write('\uFFFC');
              inlineImages.add(
                InlineImage(
                  offset: buffer.rawText.runes.length - 1,
                  media: img,
                  widthEm: w,
                  heightEm: h,
                  alt: node.attributes['alt'],
                ),
              );
              return;
            }
          }
        }
        flush();
        if (id != null && id.isNotEmpty) anchors[id] = (blocks.length, 0);
        if (img != null) {
          final size = imageSizes[img];
          blocks.add(
            ImageBlock(
              media: img,
              alt: node.attributes['alt'],
              width: size?.width,
              height: size?.height,
            ),
          );
        } else {
          _diagnostics.add(EpubDiagnosticCode.noUsableImage);
          // Visible per-image gap; remaining text and images still import.
          final alt = node.attributes['alt']?.trim();
          blocks.add(
            ParagraphBlock(text: alt?.isNotEmpty == true ? '[$alt]' : '[▧]'),
          );
        }
        return;
      }
      if (tag == 'hr') {
        whitespace = previousWhitespace;
        visible = previousVisible;
        flush();
        blocks.add(DividerBlock(box: activeBox));
        return;
      }
      if (tag == 'br') {
        explicitGapEm += (richStyles[node] ?? const EpubRichStyle()).scale;
        whitespace = previousWhitespace;
        visible = previousVisible;
        buffer.write('\n');
        return;
      }
      if (tag == 'ruby') {
        final pairs = whitespace == ProseWhiteSpace.normal
            ? proseRuby(
                node,
                annotationText: (rt) => rubyAnnotation(rt, visible),
              )
            : null;
        if (pairs != null) {
          for (final pair in pairs) {
            final start = buffer.length;
            for (final child in pair.base) {
              walk(child);
            }
            rubyRanges.add(start, buffer.length, pair.annotation);
          }
          activeLink = previousLink;
          paragraphOwner = previousOwner;
          whitespace = previousWhitespace;
          visible = previousVisible;
          return;
        }
      }
      if (tag == 'rp') {
        whitespace = previousWhitespace;
        visible = previousVisible;
        return;
      }
      if (tag == 'rt') {
        whitespace = previousWhitespace;
        visible = previousVisible;
        final annotation = rubyAnnotation(node, previousVisible);
        if (annotation != null && annotation.isNotEmpty) {
          buffer.write('（$annotation）');
        }
        return;
      }
      for (final child in node.nodes) {
        walk(child);
      }
      if (boundary) flush(heading: heading);
      activeLink = previousLink;
      paragraphOwner = previousOwner;
      whitespace = previousWhitespace;
      visible = previousVisible;
    }

    walk = (node) {
      final previousBox = activeBox;
      // A single decorated container is shared across its flattened blocks.
      // Nested decorated boxes remain outside this first native subset.
      if (node is dom.Element &&
          activeBox == null &&
          (containers.contains(node.localName) ||
              paragraphs.contains(node.localName) ||
              proseHeadingLevel(node.localName) != null) &&
          node.localName != 'body') {
        final box = epubBlockBox(
          styles[node] ?? const {},
          boxGroup,
          richStyles[node] ?? const EpubRichStyle(),
        );
        if (box != null) {
          flush();
          activeBox = box;
          boxGroup++;
        }
      }
      visit(node);
      activeBox = previousBox;
    };
    walk(doc.body!);
    flush();
    if (!blocks.any(
      (b) => b is ImageBlock || b is ParagraphBlock && b.text.trim().isNotEmpty,
    )) {
      for (var i = 0; i < blocks.length; i++) {
        if (blocks[i] case HeadingBlock(:final text, :final alignment)) {
          blocks[i] = ParagraphBlock(
            text: text,
            alignment: alignment,
            inlineImages: blocks[i].inlineImages,
            inlineRuby: blocks[i].inlineRuby,
            inlineStyles: blocks[i].inlineStyles,
            box: blocks[i].box,
          );
        }
      }
    }
    if (!blocks.any(
      (b) => b is ImageBlock || b is ParagraphBlock && b.text.trim().isNotEmpty,
    )) {
      skippedEmptyPaths.add(path);
      presentations.remove(
        LocalBookIdentity.chapter(book, 'epub:$path').chapterId,
      );
      return;
    }
    // EPUB authors often use h4–h6 for the document's chapter heading.
    // Promote only an opening heading at the document's highest heading rank.
    if (blocks.firstOrNull case HeadingBlock(
      :final text,
      :final level,
      :final alignment,
    )) {
      if (level > 2 &&
          !blocks.whereType<HeadingBlock>().any((h) => h.level < level)) {
        blocks[0] = HeadingBlock(
          text: text,
          level: 2,
          alignment: alignment,
          inlineImages: blocks[0].inlineImages,
          inlineRuby: blocks[0].inlineRuby,
          inlineStyles: blocks[0].inlineStyles,
          box: blocks[0].box,
        );
      }
    }
    final title = doc
        .querySelectorAll('h1,h2,h3,h4,h5,h6')
        .where((heading) {
          for (dom.Element? node = heading; node != null; node = node.parent) {
            if (node.attributes.containsKey('hidden') ||
                styles[node]?['display'] == 'none') {
              return false;
            }
          }
          return true;
        })
        .firstOrNull
        ?.text
        .trim();
    final docTitle = doc.querySelector('title')?.text.trim();
    final chapter = ChapterContent(
      key: LocalBookIdentity.chapter(book, 'epub:$path'),
      title: title?.isNotEmpty == true
          ? title!
          : docTitle?.isNotEmpty == true
          ? docTitle!
          : filenameTitle(path),
      blocks: blocks,
    );
    for (final hotspot in svgHotspots) {
      if (++linkCount > 10000) zipLimit();
      (String, String?)? ref;
      LocalLinkUnavailable? unavailable;
      try {
        ref = epubReference(path, hotspot.href);
        if (ref == null) unavailable = LocalLinkUnavailable.external;
      } on FormatException {
        unavailable = LocalLinkUnavailable.unsupported;
      }
      final records = rawLinks[path] ??= [];
      (_linkRegions[path] ??= {})[records.length] = hotspot.region;
      records.add((
        0,
        hotspot.label,
        ref?.$1,
        ref?.$2,
        unavailable,
        null,
        null,
      ));
      if (ref != null) requestedPaths.add(ref.$1);
    }
    chapters.add(chapter);
    chapterPaths[chapter.key] = path;
    byPath[path] = chapter;
    fragments[path] = {
      for (final e in anchors.entries)
        if (e.value.$1 < chapter.blocks.length)
          e.key: (chapter.blocks[e.value.$1].blockKey, e.value.$2),
    };
  }

  int navCount = 0;
  LocalNavigationEntry? _target(
    String base,
    String href,
    String title,
    List<LocalNavigationEntry> children,
  ) {
    if (++navCount > 10000) zipLimit();
    final ref = href.isEmpty ? null : epubReference(base, href);
    final chapter = ref == null ? null : byPath[ref.$1];
    if (chapter == null) {
      if (href.isNotEmpty) {
        _diagnostics.add(EpubDiagnosticCode.missingNavigationTarget);
      }
      if (children.isEmpty) return null;
      return LocalNavigationEntry(
        title: title.trim().isEmpty ? children.first.title : title.trim(),
        chapterKey: children.first.chapterKey,
        blockKey: children.first.blockKey,
        children: children,
      );
    }
    if (ref!.$2?.isNotEmpty == true && fragments[ref.$1]?[ref.$2] == null) {
      _diagnostics.add(EpubDiagnosticCode.missingFragment);
    }
    return LocalNavigationEntry(
      title: title.trim().isEmpty ? chapter.title : title.trim(),
      chapterKey: chapter.key,
      blockKey: fragments[ref.$1]?[ref.$2]?.$1,
      children: children,
    );
  }

  // XML whitespace only: preserve intentional NBSP and ideographic spaces.
  static String _labelWhitespace(String value) => value
      .replaceAll(RegExp(r'[ \t\r\n]+'), ' ')
      .replaceAll(RegExp(r'^ | $'), '');

  static String _navigationLabel(dom.Node node) {
    if (node is dom.Text) return node.data;
    if (node is dom.Element) {
      final accessible = node.attributes['aria-label'];
      if (accessible != null && _labelWhitespace(accessible).isNotEmpty) {
        return _labelWhitespace(accessible);
      }
      if (node.localName == 'img') return node.attributes['alt'] ?? '';
      if (node.localName == 'br') return ' ';
      if (node.localName == 'script' || node.localName == 'style') return '';
    }
    return node.nodes.map(_navigationLabel).join();
  }

  List<LocalNavigationEntry> _nav(dom.Element ol, String base, int depth) {
    if (depth > 32) zipLimit();
    final result = <LocalNavigationEntry>[];
    for (final li in ol.children.where((e) => e.localName == 'li')) {
      final a = li.children
          .where((e) => e.localName == 'a' || e.localName == 'span')
          .firstOrNull;
      final nested = li.children.where((e) => e.localName == 'ol').firstOrNull;
      final children = nested == null
          ? <LocalNavigationEntry>[]
          : _nav(nested, base, depth + 1);
      final entry = _target(
        base,
        a?.attributes['href'] ?? '',
        a == null ? '' : _labelWhitespace(_navigationLabel(a)),
        children,
      );
      if (entry != null) result.add(entry);
    }
    return result;
  }

  List<LocalNavigationEntry> _ncx(XmlElement node, String base, int depth) {
    if (depth > 32) zipLimit();
    final result = <LocalNavigationEntry>[];
    for (final point in packageChildren(node, 'navPoint')) {
      final label = packageChildren(point, 'navLabel').firstOrNull;
      final source = packageChildren(point, 'content').firstOrNull;
      final entry = _target(
        base,
        source == null ? '' : attr(source, 'src') ?? '',
        _labelWhitespace(label?.innerText ?? ''),
        _ncx(point, base, depth + 1),
      );
      if (entry != null) result.add(entry);
    }
    return result;
  }
}

class _Item {
  _Item(this.path, this.type, this.properties, this.fallback);
  final String? fallback;
  final String? path;
  final String type;
  final Set<String> properties;
}
