import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import '../../../domain/contracts/local_book_decoder.dart';
import '../../../domain/contracts/local_books.dart';
import '../../../domain/models/models.dart';
import '../txt/txt_decoder.dart';
import '../txt/txt_parser.dart' show filenameTitle;
import 'epub_zip.dart';
import 'epub_presentation.dart';
import 'epub_text_styles.dart';

final class ParsedEpub {
  ParsedEpub(this.content, this.media);
  final LocalBookContent content;
  final Map<String, Uint8List> media;
}

/// Only package-local references are returned. External resources are never
/// resolved or fetched. Percent decoding happens once, before containment.
(String, String?)? epubReference(String base, String reference) {
  final uri = Uri.tryParse(reference);
  if (uri == null || uri.hasScheme || uri.hasAuthority || uri.hasQuery) {
    return null;
  }
  final raw = Uri.decodeComponent(uri.path);
  if (raw.startsWith('/') ||
      raw.contains('\\') ||
      raw.contains('\x00') ||
      raw.contains(':')) {
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
  return (
    normalized.join('/'),
    uri.hasFragment ? Uri.decodeComponent(uri.fragment) : null,
  );
}

Iterable<XmlElement> elements(XmlNode node, String name) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
String? attr(XmlElement e, String name) {
  for (final a in e.attributes) {
    if (a.name.local == name) return a.value;
  }
  return null;
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
  final media = <String, Uint8List>{};
  final mediaByPath = <String, MediaRef>{};
  final items = <String, _Item>{};
  final chapters = <ChapterContent>[];
  final presentations = <String, String>{};
  final byPath = <String, ChapterContent>{};
  final fragments = <String, Map<String, String>>{};
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
    return XmlDocument.parse(
      input.replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), ''),
    );
  }

  String requiredPath(String base, String href) =>
      epubReference(base, href)?.$1 ?? (invalidZip());

  MediaRef? image(String path) {
    if (mediaByPath.containsKey(path)) return mediaByPath[path];
    if (!zip.entries.containsKey(path)) return null;
    final b = zip.read(path);
    // Native raster decoder supports these formats; SVG is deliberately not
    // passed to a browser, and a missing/unsupported image stays a local gap.
    final raster =
        b.length >= 4 &&
        (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47 ||
            b[0] == 0xff && b[1] == 0xd8 ||
            b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 ||
            b.length >= 12 &&
                ascii.decode(b.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
                ascii.decode(b.sublist(8, 12), allowInvalid: true) == 'WEBP');
    if (!raster) return null;
    final hash = sha256.convert(b).toString();
    if (!media.containsKey(hash)) {
      mediaSize += b.length;
      if (mediaSize > 128 * 1024 * 1024) zipLimit();
      media[hash] = b;
    }
    return mediaByPath[path] = MediaRef(
      sourceId: book.sourceId,
      mediaId: '${book.novelId}/$hash',
    );
  }

  ParsedEpub parse() {
    if (utf8.decode(zip.read('mimetype', limit: 100)) !=
        'application/epub+zip') {
      invalidZip();
    }
    if (zip.entries['mimetype']!.method != 0) invalidZip();
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
    final roots = elements(
      container,
      'rootfile',
    ).where((e) => attr(e, 'media-type') == 'application/oebps-package+xml');
    if (roots.isEmpty) invalidZip();
    final opfPath = requiredPath('', attr(roots.first, 'full-path') ?? '');
    final opf = xml(opfPath);
    if (opf.rootElement.name.local != 'package') invalidZip();
    for (final meta in elements(opf, 'meta')) {
      if (attr(meta, 'property') == 'rendition:layout' &&
              meta.innerText.trim() == 'pre-paginated' ||
          attr(meta, 'name') == 'fixed-layout' &&
              attr(meta, 'content') == 'true') {
        throw const LocalParseException(LocalParseProblem.fixedLayout);
      }
    }
    for (final e in elements(opf, 'item')) {
      final id = attr(e, 'id'), href = attr(e, 'href');
      if (id == null || href == null || items.containsKey(id)) invalidZip();
      final path = epubReference(opfPath, href)?.$1;
      items[id] = _Item(
        path,
        attr(e, 'media-type') ?? '',
        (attr(e, 'properties') ?? '').split(RegExp(r'\s+')).toSet(),
      );
    }
    final spine = elements(opf, 'spine').firstOrNull;
    if (spine == null) invalidZip();
    for (final ref in elements(spine, 'itemref')) {
      if ((attr(ref, 'properties') ?? '').contains(
        'rendition:layout-pre-paginated',
      )) {
        throw const LocalParseException(LocalParseProblem.fixedLayout);
      }
      final item = items[attr(ref, 'idref')];
      if (item == null ||
          item.path == null ||
          !{'application/xhtml+xml', 'text/html'}.contains(item.type)) {
        invalidZip();
      }
      if (byPath.containsKey(item.path)) invalidZip();
      _chapter(item.path!);
    }
    if (chapters.isEmpty) invalidZip();
    final navItem = items.values
        .where((e) => e.properties.contains('nav'))
        .firstOrNull;
    var navigation = <LocalNavigationEntry>[];
    if (navItem?.path case final path?) {
      final doc = _html(path);
      final toc = doc
          .querySelectorAll('nav')
          .where(
            (n) => (n.attributes['epub:type'] ?? n.attributes['type'] ?? '')
                .split(RegExp(r'\s+'))
                .contains('toc'),
          )
          .firstOrNull;
      final list = toc?.querySelector('ol');
      if (list != null) navigation = _nav(list, path, 0);
    } else {
      final ncx =
          items[attr(spine, 'toc')] ??
          items.values
              .where((e) => e.type == 'application/x-dtbncx+xml')
              .firstOrNull;
      if (ncx?.path case final path?) {
        final map = elements(xml(path), 'navMap').firstOrNull;
        if (map != null) navigation = _ncx(map, path, 0);
      }
    }
    if (navigation.isEmpty) {
      navigation = [
        for (final c in chapters)
          LocalNavigationEntry(title: c.title, chapterKey: c.key),
      ];
    }
    var coverItem = items.values
        .where((e) => e.properties.contains('cover-image'))
        .firstOrNull;
    final coverMeta = elements(
      opf,
      'meta',
    ).where((e) => attr(e, 'name') == 'cover').firstOrNull;
    coverItem ??= items[coverMeta == null ? null : attr(coverMeta, 'content')];
    final cover = coverItem?.path == null ? null : image(coverItem!.path!);
    final titles = elements(
      opf,
      'title',
    ).map((e) => e.innerText.trim()).where((e) => e.isNotEmpty);
    final content = LocalBookContent(
      detail: NovelDetail(
        summary: NovelSummary(
          key: book,
          title: titles.firstOrNull ?? filenameTitle(filename),
          cover: cover,
          authors: elements(
            opf,
            'creator',
          ).map((e) => e.innerText.trim()).where((e) => e.isNotEmpty),
        ),
        synopsis: elements(opf, 'description').firstOrNull?.innerText ?? '',
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
    return ParsedEpub(content, media);
  }

  dom.Document _html(String path) {
    final input = text(path);
    textSize += input.length;
    if (textSize > 12 * 1024 * 1024) zipLimit();
    if (RegExp(r'<!\s*ENTITY', caseSensitive: false).hasMatch(input)) {
      invalidZip();
    }
    final document = html.parse(input);
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

  void _chapter(String path) {
    final doc = _html(path);
    final styles = epubTextStyles(doc, [
      for (final link in doc.querySelectorAll('link[rel="stylesheet"]'))
        if (epubReference(path, link.attributes['href'] ?? '') case final ref?)
          if (zip.entries.containsKey(ref.$1)) text(ref.$1),
      for (final style in doc.querySelectorAll('style')) style.text,
    ]);
    dom.Element? paragraphOwner;
    String? property(String name) {
      for (var node = paragraphOwner; node != null; node = node.parent) {
        if (styles[node]?[name] case final value?) return value;
      }
      return null;
    }

    final presentation = includePresentations
        ? epubPresentation(
            doc,
            path,
            (p) => zip.entries.containsKey(p) ? text(p) : '',
            (p) => zip.entries.containsKey(p)
                ? zip.read(p, limit: 8 * 1024 * 1024)
                : Uint8List(0),
            (base, href) => epubReference(base, href)?.$1,
          )
        : null;
    if (presentation != null) {
      presentations[LocalBookIdentity.chapter(book, 'epub:$path').chapterId] =
          presentation;
    }

    final blocks = <ContentBlock>[];
    final anchors = <String, int>{};
    var buffer = StringBuffer();
    var pre = false;
    void flush({int? heading}) {
      final value = buffer.toString();
      buffer = StringBuffer();
      if (value.trim().isEmpty) return;
      blocks.add(
        heading == null
            ? ParagraphBlock(
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
    void walk(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(
          pre ? node.text : node.text.replaceAll(RegExp(r'\s+'), ' '),
        );
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName ?? '';
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
          node.attributes.containsKey('hidden')) {
        return;
      }
      final heading = RegExp(r'^h[1-6]$').hasMatch(tag)
          ? int.parse(tag[1])
          : null;
      final boundary =
          {'img', 'image', 'hr'}.contains(tag) ||
          containers.contains(tag) ||
          paragraphs.contains(tag) ||
          heading != null;
      if (boundary) flush();
      final previousOwner = paragraphOwner;
      if (paragraphs.contains(tag) || heading != null) paragraphOwner = node;
      final id = node.id.isNotEmpty ? node.id : node.attributes['name'];
      if (id != null && id.isNotEmpty) {
        anchors.putIfAbsent(id, () => blocks.length);
      }
      if (tag == 'img' || tag == 'image') {
        flush();
        final href =
            node.attributes['src'] ??
            node.attributes['href'] ??
            node.attributes['xlink:href'];
        final ref = href == null ? null : epubReference(path, href);
        final img = ref == null ? null : image(ref.$1);
        if (img != null) {
          blocks.add(ImageBlock(media: img, alt: node.attributes['alt']));
        } else {
          // Visible per-image gap; remaining text and images still import.
          final alt = node.attributes['alt']?.trim();
          blocks.add(
            ParagraphBlock(text: alt?.isNotEmpty == true ? '[$alt]' : '[▧]'),
          );
        }
        return;
      }
      if (tag == 'hr') {
        flush();
        blocks.add(DividerBlock());
        return;
      }
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }
      final wasPre = pre;
      if (tag == 'pre') pre = true;
      for (final child in node.nodes) {
        walk(child);
      }
      if (boundary) flush(heading: heading);
      paragraphOwner = previousOwner;
      pre = wasPre;
    }

    walk(doc.body!);
    flush();
    if (!blocks.any(
      (b) => b is ImageBlock || b is ParagraphBlock && b.text.trim().isNotEmpty,
    )) {
      for (var i = 0; i < blocks.length; i++) {
        if (blocks[i] case HeadingBlock(:final text)) {
          blocks[i] = ParagraphBlock(text: text);
        }
      }
    }
    final title = doc.querySelector('h1,h2,h3')?.text.trim();
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
    chapters.add(chapter);
    byPath[path] = chapter;
    fragments[path] = {
      for (final e in anchors.entries)
        if (e.value < chapter.blocks.length)
          e.key: chapter.blocks[e.value].blockKey,
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
    final ref = epubReference(base, href);
    final chapter = ref == null ? null : byPath[ref.$1];
    if (chapter == null) {
      if (children.isEmpty) return null;
      return LocalNavigationEntry(
        title: title.trim().isEmpty ? children.first.title : title.trim(),
        chapterKey: children.first.chapterKey,
        blockKey: children.first.blockKey,
        children: children,
      );
    }
    return LocalNavigationEntry(
      title: title.trim().isEmpty ? chapter.title : title.trim(),
      chapterKey: chapter.key,
      blockKey: fragments[ref!.$1]?[ref.$2],
      children: children,
    );
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
        a?.text ?? '',
        children,
      );
      if (entry != null) result.add(entry);
    }
    return result;
  }

  List<LocalNavigationEntry> _ncx(XmlNode node, String base, int depth) {
    if (depth > 32) zipLimit();
    final result = <LocalNavigationEntry>[];
    for (final point in node.children.whereType<XmlElement>().where(
      (e) => e.name.local == 'navPoint',
    )) {
      final label = point.children
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'navLabel')
          .firstOrNull;
      final source = point.children
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'content')
          .firstOrNull;
      final entry = _target(
        base,
        source == null ? '' : attr(source, 'src') ?? '',
        label?.innerText ?? '',
        _ncx(point, base, depth + 1),
      );
      if (entry != null) result.add(entry);
    }
    return result;
  }
}

class _Item {
  _Item(this.path, this.type, this.properties);
  final String? path;
  final String type;
  final Set<String> properties;
}
