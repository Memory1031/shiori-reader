import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import '../../tool/epub_audit/audit.dart';
import '../../tool/epub_audit/report.dart';
import '../../tool/epub_audit/source.dart';
import '../data/local/epub_css_comments_test.dart' show cssBytes, styledFiles;
import '../data/local/support/epub_fixtures.dart';
import 'epub_audit_test.dart' show changed, findings, traced;

void main() {
  const comment = '/* 制作注释：\x00\x01\x08\x0b\x0e\x1f\x7f */';
  const encodings = ['utf8', 'utf8-bom', 'utf16le', 'utf16be'];
  final encodingError = throwsA(
    isA<LocalParseException>().having(
      (e) => e.problem,
      'problem',
      LocalParseProblem.encoding,
    ),
  );

  for (final encoding in encodings) {
    for (final imported in [false, true]) {
      test('CSS comment tolerance completes later source checks '
          '($encoding, import=$imported)', () {
        final files = styledFiles(
          cssBytes(
            imported
                ? '$comment @import "base-style";'
                : '$comment p{text-align:center;}',
            encoding,
          ),
        );
        if (imported) {
          files['OPS/text/base-style'] = cssBytes(
            '$comment p{text-align:center;}',
            encoding,
          );
        }
        files['OPS/text/b.xhtml'] = utf8.encode(
          '<html><body><p id="b"><a href="a.xhtml#one">Later link.</a></p>'
          '<p>Later body.</p></body></html>',
        );
        final bytes = zipFiles(files);
        final parser = traced(bytes);
        final parsed = parser.parse();
        expect(
          (parsed.content.chapters.first.blocks.first as ParagraphBlock)
              .alignment,
          ParagraphAlignment.center,
        );
        final report = auditBytes(bytes);
        expect(report['status'], 'parsed');
        expect(report['truncationReasons'], isEmpty);
        expect(report['auditComplete'], true);
        expect(
          (report['documents'] as List).singleWhere(
            (d) => d['path'] == 'OPS/text/b.xhtml',
          )['coverage'],
          'pass',
        );
        expect(report['metrics']['simpleTextBlocksChecked'], 4);
        expect(report['checks']['text']['status'], 'pass');
        expect(report['checks']['links']['checked'], greaterThanOrEqualTo(2));
        expect(report['checks']['links']['failed'], 0);

        // Output-only faults in the later document must remain detectable.
        final later = parsed.content.chapters.last;
        final missingText = auditParsed(
          parser,
          changed(
            parsed,
            chapters: [
              parsed.content.chapters.first,
              ChapterContent(
                key: later.key,
                title: later.title,
                blocks: later.blocks.take(1),
              ),
            ],
          ),
        );
        expect(missingText['auditComplete'], true);
        expect(
          findings(
            missingText,
            'text.simple_block_mismatch',
          ).single['document'],
          'OPS/text/b.xhtml',
        );
        final missingLink = auditParsed(
          parser,
          changed(
            parsed,
            links: parsed.content.links
                .where((link) => link.source != later.key)
                .toList(),
          ),
        );
        expect(missingLink['auditComplete'], true);
        expect(
          findings(missingLink, 'link.relationship_missing').single['document'],
          'OPS/text/b.xhtml',
        );
      });
    }
  }

  test('auditor rejects CSS controls outside comments in every encoding', () {
    for (final encoding in encodings) {
      final source = SourceInventory(
        zipFiles(styledFiles(cssBytes('$comment p{\x01color:red;}', encoding))),
        const AuditOptions(),
      );
      expect(
        () => source.text('OPS/text/screen-style', css: true),
        encodingError,
        reason: encoding,
      );
    }
  });

  test('auditor rejects malformed Unicode even inside CSS comments', () {
    for (final bytes in [
      [...utf8.encode('/*'), 0xff, ...utf8.encode('*/')],
      [
        ...cssBytes('/*', 'utf16le'),
        0x00,
        0xd8,
        ...cssBytes('*/', 'utf16le').skip(2),
      ],
      [...cssBytes('/*\x01*/', 'utf16be'), 0],
    ]) {
      final source = SourceInventory(
        zipFiles(styledFiles(bytes)),
        const AuditOptions(),
      );
      expect(
        () => source.text('OPS/text/screen-style', css: true),
        encodingError,
      );
    }
  });

  test('auditor keeps non-CSS source decoding strict', () {
    final files = styledFiles(utf8.encode('$comment p{text-align:center;}'));
    files['OPS/text/b.xhtml'] = utf8.encode('<p>Body /*\x01*/</p>');
    final source = SourceInventory(zipFiles(files), const AuditOptions());
    expect(() => source.text('OPS/text/b.xhtml'), encodingError);
  });
}
