import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/txt/txt_decoder.dart';
import 'package:shiori/data/local/txt/txt_parser.dart';
import 'package:shiori/data/local/txt/txt_headings.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'parsers_test.dart' show utf16, original, problem;

final key = LocalBookIdentity.book('b' * 64);
void main() {
  test('packed line ranges preserve mixed newlines and UTF16 offsets', () {
    const text = '甲\r\n\r\n😀\r乙\n尾';
    final lines = txtLines(text, () => throw StateError('Unexpected limit'));
    expect(lines.map((line) => (line.start, line.end)), [
      (0, 3),
      (3, 5),
      (5, 8),
      (8, 10),
      (10, 11),
    ]);
    expect(
      lines.map((line) => text.substring(line.start, line.end)).join(),
      text,
    );
    expect(() => lines[0] = const TxtLine(0, 0), throwsUnsupportedError);
  });
  test('line budget accepts its boundary and rejects a final extra line', () {
    final text = 'a\n' * maxTxtLines;
    Never tooMany() =>
        throw const LocalParseException(LocalParseProblem.structureLimit);
    final lines = txtLines(text, tooMany);
    expect(lines, hasLength(maxTxtLines));
    expect(lines.last.end, text.length);
    expect(
      () => txtLines('$text尾', tooMany),
      throwsA(
        isA<LocalParseException>().having(
          (e) => e.problem,
          'problem',
          LocalParseProblem.structureLimit,
        ),
      ),
    );
  });
  test('too many explicit chapters reports a structure limit', () {
    final text = List.generate(
      maxTxtChapters + 1,
      (i) => 'Chapter ${i + 1}\n正文\n',
    ).join();
    expect(
      () => parseTxt(utf8.encode(text), key, 'x.txt', TxtEncoding.utf8),
      throwsA(
        isA<LocalParseException>().having(
          (e) => e.problem,
          'problem',
          LocalParseProblem.structureLimit,
        ),
      ),
    );
  });
  test('long previews expose head middle tail without cutting Unicode', () {
    final text = '${'甲' * 300}😀中间𠮷${'乙' * 300}尾部';
    final sample = txtPreviewSample(text);
    expect(sample, startsWith('甲'));
    expect(sample, contains('😀中间𠮷'));
    expect(sample, endsWith('尾部'));
    expect(sample.runes.length, 600);
  });
  for (final le in [true, false]) {
    test(
      'unmarked UTF16 ${le ? 'LE' : 'BE'} with a strong lane is automatic',
      () {
        final bytes = utf16('Chapter 1\n中文😀𠮷\n', le: le).sublist(2);
        final preview = inspectTxt(bytes, null);
        final encoding = le ? TxtEncoding.utf16le : TxtEncoding.utf16be;
        expect(preview.samples[encoding], 'Chapter 1\n中文😀𠮷\n');
        expect(preview.detected, encoding);
        expect(inspectTxt(bytes, encoding).samples.keys, [encoding]);
      },
    );
  }
  test(
    'ASCII is not guessed as UTF16 and invalid suffix is never selectable',
    () {
      expect(txtUtf16Candidates(utf8.encode('plain ASCII text')), isEmpty);
      expect(
        () => inspectTxt([...utf8.encode('A' * 2000), 255], TxtEncoding.utf8),
        throwsA(isA<LocalParseException>()),
      );
    },
  );
  test('UTF16 evidence after the first 2048 code units is counted', () {
    final bytes = utf16('${'中' * 2500}${'a' * 1600}').sublist(2);
    expect(inspectTxt(bytes, null).detected, TxtEncoding.utf16le);
  });
  test('all encodings clean the same controls without dropping a suffix', () {
    const before = '\x1a中\x01\x08\x1b[31m文\x1a\t\x7f\r\n\x1a\r尾\x0b页\x0c尾\x1a';
    const after = '中[31m文\t\n\n尾\n页\x0c尾';
    for (final encoding in TxtEncoding.values) {
      final bytes = switch (encoding) {
        TxtEncoding.utf8 => utf8.encode(before),
        TxtEncoding.utf16le => utf16(before),
        TxtEncoding.utf16be => utf16(before, le: false),
        TxtEncoding.gb18030 => [
          for (final point in before.runes)
            ...switch (point) {
              0x4e2d => [0xd6, 0xd0],
              0x6587 => [0xce, 0xc4],
              0x5c3e => [0xce, 0xb2],
              0x9875 => [0xd2, 0xb3],
              _ => [point],
            },
        ],
      };
      expect(inspectTxt(bytes, encoding).samples[encoding], after);
      expect(original(parseTxt(bytes, key, 'x.txt', encoding)), after);
    }
  });
  test('content erased by cleanup is invalid, not an encoding failure', () {
    final bytes = utf8.encode('\x1a\r\x0b\x7f\t　');
    expect(
      () => inspectTxt(bytes, null),
      throwsA(problem(LocalParseProblem.invalid)),
    );
    expect(
      () => parseTxt(bytes, key, 'x.txt', TxtEncoding.utf8),
      throwsA(problem(LocalParseProblem.invalid)),
    );
  });
  test('actual NUL and malformed BOM tails still fail for TXT', () {
    for (final bytes in [
      utf16('A\u0000B'),
      [...utf16('A' * 1000), 0x00, 0xd8],
      [0xef, 0xbb, 0xbf, ...utf8.encode('A' * 1000), 0xff],
    ]) {
      expect(
        () => inspectTxt(bytes, null),
        throwsA(problem(LocalParseProblem.encoding)),
      );
    }
  });
  test('resource decode is unchanged and TXT keeps the second BOM as text', () {
    final bytes = utf8.encode('\ufeff\ufeff正文');
    expect(decodeTxt(bytes, TxtEncoding.utf8), '正文');
    expect(
      original(parseTxt(bytes, key, 'x.txt', TxtEncoding.utf8)),
      '\ufeff正文',
    );
    expect(
      () => decodeTxt(utf8.encode('正文\x1a'), TxtEncoding.utf8),
      throwsA(problem(LocalParseProblem.encoding)),
    );
  });
  test(
    'clean headings keep original scalar offsets and Unicode in body blocks',
    () {
      const body = '　\u00a0\t😀\u200c\u200d\u200f\ufe0f�\ufeff';
      const text = '第一章\r\n$body\x1a\r\x1a\n第\x1a二章\r\n后文';
      final parsed = parseTxt(
        utf8.encode(text),
        key,
        'x.txt',
        TxtEncoding.utf8,
      );
      final offset = text.substring(0, text.indexOf('第\x1a二章')).runes.length;
      expect(
        parsed.chapters.last.key,
        LocalBookIdentity.chapter(key, 'txt:$offset'),
      );
      expect(parsed.chapters.last.title, '第二章');
      expect(original(parsed), '第一章\n$body\n\n第二章\n后文');
      expect(
        original(parsed),
        inspectTxt(
          utf8.encode(text),
          TxtEncoding.utf8,
        ).samples[TxtEncoding.utf8],
      );
    },
  );
  test('prose false positives stay in one chapter with exact text', () {
    const text =
        '正文\n第十二章的时候，我终于明白了。\n第一章 说的是谁？\n番外的话还是以后再说\nChapter 1 was mentioned in this sentence.\n结束';
    final c = parseTxt(utf8.encode(text), key, 'x.txt', TxtEncoding.utf8);
    expect(c.chapters, hasLength(1));
    expect(original(c), text);
  });
  for (final heading in [
    '第一章',
    '第０１章',
    '第一話',
    '卷一',
    '序章',
    '特典',
    '間章',
    '幕間',
    'Chapter 1',
    'Part IV',
    'Volume 2',
    'Prologue',
    'Epilogue',
  ]) {
    test('explicit short or single heading remains supported: $heading', () {
      final c = parseTxt(
        utf8.encode('$heading\n短\n終章\n尾'),
        key,
        'x.txt',
        TxtEncoding.utf8,
      );
      expect(c.chapters, hasLength(2));
      expect(c.chapters.first.title, heading);
    });
  }
  test('attached ambiguous titles need repeated isolated context', () {
    final text = '第一章夏日\n正文\n第二章夜晚\n正文';
    expect(
      parseTxt(utf8.encode(text), key, 'x.txt', TxtEncoding.utf8).chapters,
      hasLength(1),
    );
    final isolated = '第一章夏日\n\n正文\n\n第二章夜晚\n\n正文';
    expect(
      parseTxt(utf8.encode(isolated), key, 'x.txt', TxtEncoding.utf8).chapters,
      hasLength(2),
    );
  });
  test('dense speculative candidates do not create thousands of chapters', () {
    final text = List.generate(2000, (i) => '第${i + 1}章时候').join('\n');
    final c = parseTxt(utf8.encode(text), key, 'x.txt', TxtEncoding.utf8);
    expect(c.chapters, hasLength(1));
    expect(original(c), text);
  });
  test(
    'source offsets count scalars before CRLF normalization and preserve inner BOM',
    () {
      const text = '😀𠮷\r\n\r\n第一章\r\n正文\ufeff\r\n第二章\r\n尾';
      for (final encoding in [
        TxtEncoding.utf8,
        TxtEncoding.utf16le,
        TxtEncoding.utf16be,
      ]) {
        final bytes = encoding == TxtEncoding.utf8
            ? utf8.encode(text)
            : utf16(text, le: encoding == TxtEncoding.utf16le);
        final c = parseTxt(bytes, key, 'x.txt', encoding);
        final offset = text.substring(0, text.indexOf('第二章')).runes.length;
        expect(
          c.chapters.last.key,
          LocalBookIdentity.chapter(key, 'txt:$offset'),
        );
        expect(original(c), text.replaceAll('\r\n', '\n'));
        expect(
          parseTxt(bytes, key, 'x.txt', encoding).chapters.map((c) => c.key),
          c.chapters.map((c) => c.key),
        );
      }
    },
  );
}
