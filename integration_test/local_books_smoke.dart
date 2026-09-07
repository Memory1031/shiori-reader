// Offline LOCAL-001 probe. Separate development root; no production Source.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

T value<T>(Result<T> result) => (result as Success<T>).value;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String status;
  var step = 'open';
  LocalDatabases? databases;
  try {
    final support = await getApplicationSupportDirectory();
    final paths = AppPaths(
      support: Directory('${support.path}/local001-probe'),
      temporary: await getTemporaryDirectory(),
      environment: StorageEnvironment.development,
    );
    databases = value<LocalDatabases>(await LocalDatabases.open(paths));
    final store = databases.localBooks;
    final bytes = utf8.encode('LOCAL-001 self-authored offline original v1');
    final key = LocalBookIdentity.book(sha256.convert(bytes).toString());
    final token = CancellationSource().token;
    step = 'read';
    final existing = value(await store.read(key, cancellation: token));
    step = 'import';
    final imported = value(
      await store.importBook(
        bytes: Stream.value(bytes),
        format: LocalBookFormat.txt,
        cancellation: token,
        parse: (s) async {
          if (existing != null) throw StateError('Duplicate reparsed');
          final media = await s.writeMedia(Stream.value([10, 20, 30]));
          final chapter = LocalBookIdentity.chapter(s.key, 'txt:0');
          return LocalBookContent(
            detail: NovelDetail(
              summary: NovelSummary(
                key: s.key,
                title: 'Offline owned book',
                cover: media,
              ),
            ),
            catalog: Catalog(
              novelKey: s.key,
              volumes: [
                Volume(
                  groupId: 'body',
                  chapters: [
                    Chapter(
                      key: chapter,
                      title: 'One',
                      ordinal: 0,
                      volumeGroupId: 'body',
                    ),
                  ],
                ),
              ],
            ),
            chapters: [
              ChapterContent(
                key: chapter,
                title: 'One',
                blocks: [ParagraphBlock(text: 'Offline original')],
              ),
            ],
          );
        },
      ),
    );
    step = 'media';
    final media = value(
      await store.readMedia(
        imported.content.detail.summary.cover!,
        cancellation: token,
      ),
    );
    if (media.join(',') != '10,20,30') throw StateError('Media mismatch');
    step = 'reopen';
    await databases.close();
    databases = null;
    databases = value<LocalDatabases>(await LocalDatabases.open(paths));
    final reopened = value(
      await databases.localBooks.read(key, cancellation: token),
    );
    if (reopened?.content.chapters.single != imported.content.chapters.single) {
      throw StateError('Reopen identity mismatch');
    }
    status = existing == null
        ? 'LOCAL001_PREPARE_AND_REOPEN_PASS'
        : 'LOCAL001_COLD_REOPEN_DEDUP_MEDIA_PASS';
  } catch (e) {
    status = 'LOCAL001_FAIL_${step}_${e.runtimeType}';
  } finally {
    await databases?.close();
  }
  debugPrint(status);
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text(status))),
    ),
  );
}
