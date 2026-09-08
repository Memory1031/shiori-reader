// Self-authored offline parser/storage probe. Uses a separate development root.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import '../test/data/local/support/epub_fixtures.dart';

T ok<T>(Result<T> result) => (result as Success<T>).value;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('LOCAL-003 / 004 验证中'))),
    ),
  );
  LocalDatabases? databases;
  String status;
  var step = 'open';
  final started = DateTime.now();
  try {
    final support = await getApplicationSupportDirectory();
    final probeRoot = await Directory(
      '${support.path}/local003004-probe',
    ).create(recursive: true);
    final isolated = await probeRoot.createTemp('run-');
    final paths = AppPaths(
      support: isolated,
      temporary: await getTemporaryDirectory(),
      environment: StorageEnvironment.development,
    );
    databases = ok<LocalDatabases>(await LocalDatabases.open(paths));
    final records = <LocalBookRecord>[];
    final inputs = <List<int>>[
      [239, 187, 191, ...utf8.encode('第一章 星光\r\n原文😀\r\n第二章 星海\n再见。')],
      [0xd6, 0xd0, 0xce, 0xc4, 0x94, 0x39, 0xfc, 0x36],
      [
        255,
        254,
        for (final c in 'UTF16 中文😀'.codeUnits) ...[c & 255, c >> 8],
      ],
      zipFiles(epubFiles(ncx: true)),
      zipFiles(epubFiles()),
    ];
    for (var i = 0; i < inputs.length; i++) {
      step = 'parse-$i';
      final format = i < 3 ? LocalBookFormat.txt : LocalBookFormat.epub;
      final cancellation = CancellationSource();
      final result = await databases.localBooks.importBook(
        bytes: Stream.value(inputs[i]),
        format: format,
        cancellation: cancellation.token,
        parse: (session) => const BookDecoder().decode(
          session,
          format: format,
          filename: '自建样本.${format.name}',
          cancellation: cancellation.token,
          chooseEncoding: (preview) async {
            if (!preview.samples.containsKey(TxtEncoding.gb18030)) {
              throw StateError('Missing GB preview');
            }
            return TxtEncoding.gb18030;
          },
        ),
      );
      records.add(ok(result));
    }
    if ((records[1].content.chapters.single.blocks.single as ParagraphBlock)
            .text !=
        '中文😀') {
      throw StateError('GB18030 mismatch');
    }
    step = 'reopen';
    await databases.close();
    databases = null;
    databases = ok<LocalDatabases>(await LocalDatabases.open(paths));
    for (var i = 0; i < records.length; i++) {
      step = 'read-$i';
      final saved = records[i];
      final token = CancellationSource().token;
      final reopened = ok(
        await databases.localBooks.read(
          saved.content.detail.summary.key,
          cancellation: token,
        ),
      )!;
      if (reopened.content.chapters.first.contentRevision !=
          saved.content.chapters.first.contentRevision) {
        throw StateError('Content mismatch');
      }
      if (i >= 3) {
        final image = ok(
          await databases.localBooks.readMedia(
            reopened.content.detail.summary.cover!,
            cancellation: token,
          ),
        );
        step = 'image-$i';
        final codec = await decodeImageFromList(image);
        if (codec.width != 1) throw StateError('Image decode failed');
        codec.dispose();
        step = 'anchor-$i';
        final target = reopened.content.navigation.last;
        if (target.children.first.blockKey == target.blockKey ||
            target.blockKey == null) {
          throw StateError('Anchor mismatch');
        }
      }
      step = 'dedup-$i';
      final duplicate = ok(
        await databases.localBooks.importBook(
          bytes: Stream.value(inputs[i]),
          format: saved.format,
          cancellation: token,
          parse: (_) async => throw StateError('Unexpected duplicate parse'),
        ),
      );
      if (duplicate.content.detail.summary.key !=
          saved.content.detail.summary.key) {
        throw StateError('Duplicate identity');
      }
    }
    await databases.close();
    databases = null;
    await isolated.delete(recursive: true);
    status =
        'LOCAL003004_PARSERS_REOPEN_DEDUP_IMAGE_PASS ${DateTime.now().difference(started).inMilliseconds}ms';
  } catch (error) {
    status = 'LOCAL003004_FAIL step=$step type=${error.runtimeType}';
  } finally {
    await databases?.close();
  }
  debugPrint(status);
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(status),
          ),
        ),
      ),
    ),
  );
}
