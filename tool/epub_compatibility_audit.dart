// Explicit opt-in, read-only host audit. Reports structure, never book text.
// dart run tool/epub_compatibility_audit.dart <paths.json> <report.json>
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:xml/xml.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/local/epub/epub_text_styles.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';

String compact(String text) => text.replaceAll(RegExp(r'\s+'), '');

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Expected paths JSON and output JSON');
  }
  final paths = (jsonDecode(await File(args[0]).readAsString()) as List)
      .cast<String>();
  final results = <Map<String, Object?>>[];
  for (final path in paths) {
    final file = File(path);
    final result = <String, Object?>{'file': file.uri.pathSegments.last};
    results.add(result);
    try {
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      result.addAll({'sha256': hash, 'bytes': bytes.length});
      final parser = EpubParser(
        bytes,
        NovelKey(sourceId: SourceId('local'), novelId: hash),
        file.uri.pathSegments.last,
        includePresentations: true,
      );
      final parsed = parser.parse();
      final differences = <Map<String, Object?>>[];
      final policyDifferences = <Map<String, Object?>>[];
      final missingImages = <Map<String, Object?>>[];
      final presentationImageDifferences = <String>[];
      var sourceImages = 0, outputImages = 0, ruby = 0, empty = 0;
      for (final path in parser.byPath.keys) {
        final source = parser.text(path);
        String input = source;
        // Independent XML preprocessing avoids HTML swallowing self-closed
        // script tags. The production parser uses a bounded tag normalization.
        try {
          final xml = XmlDocument.parse(
            source.replaceAllMapped(RegExp(r'&[A-Za-z][A-Za-z0-9]+;'), (m) {
              final decoded =
                  html.parseFragment(m.group(0)!).text ?? m.group(0)!;
              return decoded.runes.map((c) => '&#$c;').join();
            }),
          );
          for (final e
              in xml.descendants
                  .whereType<XmlElement>()
                  .where((e) => {'script', 'style'}.contains(e.name.local))
                  .toList()) {
            // Keep style text for the separately computed CSS map below.
            if (e.name.local == 'script') e.parent?.children.remove(e);
          }
          input = xml.toXmlString();
        } on FormatException {
          /* Malformed XHTML uses HTML fallback. */
        }
        final doc = html.parse(input);
        final styles = epubTextStyles(doc, [
          for (final link in doc.querySelectorAll('link[rel="stylesheet"]'))
            if (epubReference(path, link.attributes['href'] ?? '')
                case final r?)
              if (parser.zip.entries.containsKey(r.$1)) parser.text(r.$1),
          for (final style in doc.querySelectorAll('style')) style.text,
        ]);
        for (final node in doc.querySelectorAll('script,style,head,noscript')) {
          node.remove();
        }
        final originalText = compact(doc.body?.text ?? '');
        final chapter = parser.byPath[path]!;
        final outputText = compact(
          chapter.blocks
              .map(
                (b) => switch (b) {
                  ParagraphBlock(:final text) ||
                  HeadingBlock(:final text) => text,
                  _ => '',
                },
              )
              .join(),
        );
        final images = doc.querySelectorAll('img,image');
        final outImages = chapter.blocks.whereType<ImageBlock>().toList();
        sourceImages += images.length;
        outputImages += outImages.length;
        ruby += doc.querySelectorAll('ruby').length;
        if (originalText.isEmpty && images.isEmpty) empty++;
        if (originalText != outputText || images.length != outImages.length) {
          differences.add({
            'path': path,
            'rawTextCharacters': originalText.length,
            'parsedTextCharacters': outputText.length,
            'rawTextEqual': originalText == outputText,
            'sourceImageReferences': images.length,
            'parsedImages': outImages.length,
          });
        }
        for (final node in doc.querySelectorAll('*').toList()) {
          if (node.attributes.containsKey('hidden') ||
              styles[node]?['display'] == 'none') {
            node.remove();
          }
        }
        for (final rp in doc.querySelectorAll('rp')) {
          rp.remove();
        }
        for (final rt in doc.querySelectorAll('rt')) {
          rt.text = '（${rt.text.trim()}）';
        }
        final expectedHashes = <String>[];
        for (final img in doc.querySelectorAll('img,image')) {
          final href =
              img.attributes['src'] ??
              img.attributes['href'] ??
              img.attributes['xlink:href'] ??
              img.attributes[const dom.AttributeName(
                'xlink',
                'href',
                'http://www.w3.org/1999/xlink',
              )];
          final ref = href == null ? null : epubReference(path, href);
          if (ref != null && parser.zip.entries.containsKey(ref.$1)) {
            final hash = sha256.convert(parser.zip.read(ref.$1)).toString();
            if (parsed.media.containsKey(hash)) {
              expectedHashes.add(hash);
              continue;
            }
          }
          missingImages.add({
            'path': path,
            'reference': href,
            'exists': ref != null && parser.zip.entries.containsKey(ref.$1),
          });
          final alt = img.attributes['alt']?.trim();
          img.replaceWith(dom.Text(alt?.isNotEmpty == true ? '[$alt]' : '[▧]'));
        }
        final expectedText = compact(doc.body?.text ?? '');
        final outputHashes = outImages
            .map((b) => b.media.mediaId.split('/').last)
            .toList();
        if (parser.presentations[chapter.key.chapterId]
            case final presentation?) {
          final embedded = html.parse(presentation).querySelectorAll('img').map(
            (img) {
              final src = img.attributes['src'] ?? '';
              if (!src.startsWith('data:image/') || !src.contains(';base64,')) {
                return '';
              }
              return sha256
                  .convert(base64Decode(src.split(';base64,').last))
                  .toString();
            },
          ).toList();
          if (jsonEncode(embedded) != jsonEncode(expectedHashes)) {
            presentationImageDifferences.add(path);
          }
        }
        if (expectedText != outputText ||
            jsonEncode(expectedHashes) != jsonEncode(outputHashes)) {
          policyDifferences.add({
            'path': path,
            'textEqual': expectedText == outputText,
            'imageOrderEqual':
                jsonEncode(expectedHashes) == jsonEncode(outputHashes),
            'expectedCharacters': expectedText.length,
            'outputCharacters': outputText.length,
          });
        }
      }
      var navCount = 0, invalidTargets = 0;
      void visit(LocalNavigationEntry e) {
        navCount++;
        final chapter = parsed.content.chapters
            .where((c) => c.key == e.chapterKey)
            .firstOrNull;
        if (chapter == null ||
            (e.blockKey != null &&
                !chapter.blocks.any((b) => b.blockKey == e.blockKey))) {
          invalidTargets++;
        }
        for (final child in e.children) {
          visit(child);
        }
      }

      for (final e in parsed.content.navigation) {
        visit(e);
      }
      result.addAll({
        'status': 'parsed',
        'chapters': parsed.content.chapters.length,
        'sourceImageReferences': sourceImages,
        'parsedImages': outputImages,
        'uniqueImages': parsed.media.length,
        'nav': navCount,
        'invalidTargets': invalidTargets,
        'presentations': parser.presentations.length,
        'ruby': ruby,
        'emptyPages': empty,
        'skippedEmptyPaths': parser.skippedEmptyPaths.toList(),
        'differences': differences,
        'policyDifferences': policyDifferences,
        'presentationImageDifferences': presentationImageDifferences,
        'missingImages': missingImages,
      });
    } catch (e, stack) {
      result.addAll({
        'status': 'failed',
        'failure': e is LocalParseException
            ? e.problem.name
            : e.runtimeType.toString(),
      });
      result['frames'] = stack.toString().split('\n').take(5).toList();
    }
    stdout.writeln(
      '${results.length}/${paths.length}: ${result['status']} ${result['file']}',
    );
    await File(args[1]).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope':
            'Read-only host parser audit; raw text equality ignores whitespace, not visual equivalence',
        'samples': results,
      }),
    );
  }
}
