import 'dart:typed_data';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import 'package:shiori/data/local/epub/epub_zip.dart';
import 'package:shiori/data/local/epub/epub_parser.dart' show epubReference;
import 'package:shiori/data/local/txt/txt_decoder.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'report.dart';

final class SourceBudgetExceeded implements Exception {}

/// Independently derives source inventory, never walks parser.byPath/items.
final class SourceInventory {
  SourceInventory(Uint8List bytes, this.options) : zip = EpubZip(bytes);
  final EpubZip zip;
  final AuditOptions options;
  final items = <String, Json>{};
  final spine = <Json>[];
  final navigationPaths = <String>{};
  String? opfPath;
  int sourceCharacters = 0, cssCharacters = 0, documents = 0;
  final _cssCache = <String, String>{};
  final _documentCache = <String, dom.Document>{};
  String text(String path, {bool css = false}) {
    if (css && _cssCache.containsKey(path)) return _cssCache[path]!;
    final bytes = zip.read(path, limit: 4 * 1024 * 1024);
    final value = decodeTxt(bytes, txtBom(bytes) ?? TxtEncoding.utf8);
    if (css) {
      cssCharacters += value.length;
      if (cssCharacters > 8 * 1024 * 1024) throw SourceBudgetExceeded();
      _cssCache[path] = value;
    } else {
      sourceCharacters += value.length;
      if (sourceCharacters > 12 * 1024 * 1024) throw SourceBudgetExceeded();
    }
    return value;
  }

  void boundTree<T>(T root, Iterable<T> Function(T) children) {
    var nodes = 0;
    final stack = <(T, int)>[(root, 0)];
    while (stack.isNotEmpty) {
      final (node, depth) = stack.removeLast();
      if (++nodes > 100000 || depth > 128) throw SourceBudgetExceeded();
      for (final child in children(node)) {
        stack.add((child, depth + 1));
      }
    }
  }

  XmlDocument xml(String path) {
    final value = text(path);
    if (RegExp(
      r'<!\s*ENTITY|<!\s*DOCTYPE[^>]*\[',
      caseSensitive: false,
    ).hasMatch(value)) {
      invalidZip();
    }
    final doc = XmlDocument.parse(
      value.replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), ''),
    );
    boundTree<XmlNode>(doc, (n) => n.children);
    return doc;
  }

  dom.Document document(String path) {
    if (_documentCache[path] case final cached?) return cached;
    if (++documents > options.maxDocuments) throw SourceBudgetExceeded();
    final value = text(path);
    if (RegExp(
      r'<!\s*ENTITY|<!\s*DOCTYPE[^>]*\[',
      caseSensitive: false,
    ).hasMatch(value)) {
      invalidZip();
    }
    final doc = html.parse(
      value.replaceAll(
        RegExp(
          r'''<(?:script|style)\b(?:[^>"']|"[^"]*"|'[^']*')*/\s*>''',
          caseSensitive: false,
        ),
        '',
      ),
    );
    boundTree<dom.Node>(doc, (n) => n.nodes);
    return _documentCache[path] = doc;
  }

  Iterable<XmlElement> children(XmlElement node, String name) =>
      node.childElements.where(
        (n) =>
            n.name.local == name &&
            n.name.namespaceUri == node.name.namespaceUri,
      );
  void load() {
    final container = xml('META-INF/container.xml');
    final roots = children(container.rootElement, 'rootfiles')
        .expand((e) => children(e, 'rootfile'))
        .where(
          (e) =>
              e.getAttribute('media-type') == 'application/oebps-package+xml',
        );
    if (roots.isEmpty) invalidZip();
    opfPath = epubReference(
      '',
      roots.first.getAttribute('full-path') ?? '',
    )?.$1;
    if (opfPath == null) invalidZip();
    final package = xml(opfPath!).rootElement;
    final manifests = children(package, 'manifest').toList(),
        spines = children(package, 'spine').toList();
    if (manifests.length != 1 || spines.length != 1) invalidZip();
    for (final item in children(manifests.single, 'item')) {
      final id = item.getAttribute('id');
      if (id == null || items.containsKey(id)) invalidZip();
      final path = epubReference(opfPath!, item.getAttribute('href') ?? '')?.$1;
      final properties = (item.getAttribute('properties') ?? '').split(
        RegExp(r'\s+'),
      );
      items[id] = {
        'id': id,
        'path': path,
        'type': item.getAttribute('media-type'),
        'fallback': item.getAttribute('fallback'),
        'nav': properties.contains('nav'),
      };
      if (path != null &&
          (properties.contains('nav') ||
              item.getAttribute('media-type') == 'application/x-dtbncx+xml')) {
        navigationPaths.add(path);
      }
    }
    final occurrences = <String, int>{};
    for (final ref in children(spines.single, 'itemref')) {
      final id = ref.getAttribute('idref');
      var item = items[id];
      final chain = <String>{};
      while (item != null &&
          !{'application/xhtml+xml', 'text/html'}.contains(item['type'])) {
        if (!chain.add(item['id'] as String)) invalidZip();
        item = items[item['fallback']];
      }
      if (item == null || item['path'] == null) invalidZip();
      final path = item['path'] as String;
      final occurrence = occurrences.update(
        path,
        (n) => n + 1,
        ifAbsent: () => 0,
      );
      spine.add({
        'originalPath': items[id]?['path'],
        'selectedPath': path,
        'occurrence': occurrence,
        'linear': ref.getAttribute('linear') != 'no',
        'fallbackChain': chain.map((e) => items[e]?['path']).toList(),
        'fixed': (ref.getAttribute('properties') ?? '')
            .split(RegExp(r'\s+'))
            .contains('rendition:layout-pre-paginated'),
      });
    }
  }
}
