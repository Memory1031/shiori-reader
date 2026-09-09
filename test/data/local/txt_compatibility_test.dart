import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/txt/txt_decoder.dart';
import 'package:shiori/data/local/txt/txt_parser.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/contracts/local_books.dart';
import 'parsers_test.dart' show utf16, original;

final key = LocalBookIdentity.book('b' * 64);
void main() {
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
      'unmarked UTF16 ${le ? 'LE' : 'BE'} remains a confirmed candidate',
      () {
        final bytes = utf16('Chapter 1\n中文😀𠮷\n', le: le).sublist(2);
        final preview = inspectTxt(bytes, null);
        final encoding = le ? TxtEncoding.utf16le : TxtEncoding.utf16be;
        expect(preview.samples[encoding], 'Chapter 1\n中文😀𠮷\n');
        expect(preview.detected, isNull);
        expect(inspectTxt(bytes, encoding).samples.keys, [encoding]);
      },
    );
  }
  test(
    'ASCII is not guessed as UTF16 and invalid suffix is never selectable',
    () {
      expect(txtUtf16Hint(utf8.encode('plain ASCII text')), isNull);
      expect(
        () => inspectTxt([...utf8.encode('A' * 2000), 255], TxtEncoding.utf8),
        throwsA(isA<LocalParseException>()),
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
