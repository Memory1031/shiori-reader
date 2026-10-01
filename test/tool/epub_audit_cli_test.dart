import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../../tool/epub_audit/cli.dart';
import '../../tool/epub_audit/report.dart';
import 'support/audit_fixture.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shiori-audit-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  test(
    'Windows junction does not extend an explicitly selected directory',
    () async {
      final scope = await Directory(p.join(temp.path, 'scope')).create();
      final outside = await Directory(p.join(temp.path, 'outside')).create();
      await File(
        p.join(scope.path, 'inside.epub'),
      ).writeAsBytes(auditFixture());
      await File(
        p.join(outside.path, 'outside.epub'),
      ).writeAsBytes(auditFixture());
      final link = p.join(scope.path, 'redirect');
      final environment = {
        'SHIORI_AUDIT_LINK': link,
        'SHIORI_AUDIT_TARGET': outside.path,
      };
      final created = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        r'New-Item -ItemType Junction -Path $env:SHIORI_AUDIT_LINK -Target $env:SHIORI_AUDIT_TARGET | Out-Null',
      ], environment: environment);
      expect(created.exitCode, 0);
      try {
        expect(
          await explicitInputs({'--input-dir': scope.path}, recursive: true),
          [p.join(scope.path, 'inside.epub')],
        );
      } finally {
        await Link(link).delete();
      }
      expect(await File(p.join(outside.path, 'outside.epub')).exists(), true);
    },
    skip: !Platform.isWindows,
  );
  test(
    'explicit single/list/directory input, recursion opt-in and unicode paths',
    () async {
      final file = File(p.join(temp.path, '中文 空格.epub'));
      await file.writeAsBytes(auditFixture());
      final sub = await Directory(p.join(temp.path, 'nested')).create();
      await File(p.join(sub.path, 'two.epub')).writeAsBytes(auditFixture());
      expect(await explicitInputs({'--input': file.path}, recursive: false), [
        file.path,
      ]);
      expect(
        await explicitInputs({'--input-dir': temp.path}, recursive: false),
        hasLength(1),
      );
      expect(
        await explicitInputs({'--input-dir': temp.path}, recursive: true),
        hasLength(2),
      );
      final paths = File(p.join(temp.path, 'paths.json'));
      await paths.writeAsString(jsonEncode([file.path]));
      expect(await explicitInputs({'--paths': paths.path}, recursive: false), [
        file.path,
      ]);
    },
  );
  test(
    'new output refuses conflicts and leaves existing bytes untouched',
    () async {
      final out = await newOutput(p.join(temp.path, 'out'));
      final marker = File(p.join(out.path, 'marker'));
      await marker.writeAsString('original');
      await expectLater(
        newOutput(out.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await marker.readAsString(), 'original');
    },
  );
  test(
    'terminable worker timeout awaits actual process exit and continues',
    () async {
      final script = File(p.join(temp.path, 'wait.dart'));
      await script.writeAsString(
        'import "dart:async"; void main() {Timer(const Duration(seconds:30), (){});}',
      );
      Process? worker;
      final status = await runIsolated(
        auditDartExecutable(),
        [script.path],
        const Duration(milliseconds: 500),
        onProcess: (process) {
          if (process != null) worker = process;
        },
      );
      expect(status, 'timeout');
      expect(await worker!.exitCode, isNot(0));
      final next = await runIsolated(auditDartExecutable(), [
        '--version',
      ], const Duration(seconds: 5));
      expect(next, 'completed');
    },
  );
  test(
    'interruption terminates the worker and leaves completed journal readable',
    () async {
      final script = File(p.join(temp.path, 'wait.dart'));
      await script.writeAsString(
        'import "dart:async"; void main() {Timer(const Duration(seconds:30), (){});}',
      );
      final stop = Completer<void>();
      Timer(const Duration(milliseconds: 500), () => stop.complete());
      expect(
        await runIsolated(
          auditDartExecutable(),
          [script.path],
          const Duration(seconds: 10),
          interrupted: stop.future,
        ),
        'interrupted',
      );
      await File(p.join(temp.path, 'report.json')).writeAsString(
        jsonEncode({
          'run': {'schemaVersion': schemaVersion, 'complete': false},
          'books': [],
        }),
      );
      await File(
        p.join(temp.path, 'book-00000.json'),
      ).writeAsString(jsonEncode({'sha256': 'a', 'status': 'parsed'}));
      await File(p.join(temp.path, 'books.jsonl')).writeAsString(
        '${jsonEncode({'reportFile': 'book-00000.json'})}\n{"interrupted":',
      );
      final recovered = await readRun(temp.path);
      expect(recovered['run']['complete'], false);
      expect(recovered['books'], hasLength(1));
    },
  );
  test(
    'real isolated batch: one bad, one good, duplicate, same facts in markdown and JSON',
    () async {
      final bytes = auditFixture(body: '<p>PRIVATE_SAMPLE_BODY</p>');
      final a = File(p.join(temp.path, '好 书.epub'));
      final b = File(p.join(temp.path, '副本.epub'));
      final bad = File(p.join(temp.path, '坏 书.epub'));
      await a.writeAsBytes(bytes);
      await b.writeAsBytes(bytes);
      await bad.writeAsBytes([1, 2, 3]);
      final paths = File(p.join(temp.path, 'paths.json'));
      await paths.writeAsString(jsonEncode([bad.path, a.path, b.path]));
      final output = p.join(temp.path, 'scan');
      expect(
        await auditMain(['scan', '--paths', paths.path, '--out', output]),
        0,
      );
      final report = await readRun(output);
      expect(report['run']['totalFiles'], 3);
      expect(report['run']['uniqueEpubs'], 2);
      expect(report['run']['duplicates'], 1);
      expect(report['run']['complete'], true);
      expect(report['books'], hasLength(2));
      final json =
          jsonDecode(await File(p.join(output, 'report.json')).readAsString())
              as Json;
      expect(
        await File(p.join(output, 'report.md')).readAsString(),
        reportMarkdown(json),
      );
      expect(jsonEncode(report), isNot(contains('PRIVATE_SAMPLE_BODY')));
      final book = (report['books'] as List).firstWhere(
        (b) => b['status'] == 'parsed',
      );
      expect(book['aliases'], hasLength(2));
      final immutable =
          jsonDecode(
                await File(
                  p.join(output, book['reportFile'] as String),
                ).readAsString(),
              )
              as Json;
      expect(
        immutable['aliases'],
        hasLength(1),
        reason: 'completed reports must never be rewritten for duplicates',
      );
      expect(
        await auditMain([
          'compare',
          '--before',
          output,
          '--after',
          output,
          '--out',
          p.join(temp.path, 'diff'),
        ]),
        0,
      );
      final diff = jsonDecode(
        await File(p.join(temp.path, 'diff', 'comparison.json')).readAsString(),
      );
      expect(diff['changes'], isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('legacy arguments have a migration error without overwriting', () async {
    final target = File(p.join(temp.path, 'old.json'));
    await target.writeAsString('original');
    expect(await auditMain(['paths.json', target.path]), 64);
    expect(await target.readAsString(), 'original');
  });
  test(
    'duplicate aliases recover from journal without changing completed bytes',
    () async {
      await File(p.join(temp.path, 'report.json')).writeAsString(
        jsonEncode({
          'run': {'schemaVersion': schemaVersion, 'complete': false},
          'books': [],
        }),
      );
      final completed = File(p.join(temp.path, 'book-00000.json'));
      await completed.writeAsString(
        jsonEncode({
          'sha256': 'a',
          'status': 'parsed',
          'aliases': ['Original'],
        }),
      );
      final bytes = await completed.readAsBytes();
      await File(p.join(temp.path, 'books.jsonl')).writeAsString(
        [
          jsonEncode({
            'reportFile': 'book-00000.json',
            'aliases': ['Original'],
          }),
          jsonEncode({
            'status': 'duplicate',
            'reportFile': 'book-00000.json',
            'alias': 'Duplicate',
          }),
          '{"status":"duplicate","reportFile":',
        ].join('\n'),
      );
      // Also tolerate interruption in the middle of a UTF-8 alias character.
      await File(
        p.join(temp.path, 'books.jsonl'),
      ).writeAsBytes([0xe4, 0xb8], mode: FileMode.append);
      final recovered = await readRun(temp.path);
      expect(recovered['books'], hasLength(1));
      expect(recovered['books'][0]['aliases'], ['Original', 'Duplicate']);
      expect(await completed.readAsBytes(), bytes);
    },
  );
}
