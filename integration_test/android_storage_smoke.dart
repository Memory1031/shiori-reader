// ANDROID-002: bounded self-authored probe in an isolated development root.
// No production Source or user-book mutations. TLS opt-in is one request/run ID.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/local/preferences_app_settings_store.dart';
import 'package:shiori/data/local/preferences_settings_store.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/data/media/local_image_repository.dart';
import 'package:shiori/data/cache/cache_policy.dart';
import 'package:shiori/data/cache/local_cache_management.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/data/media/persistent_image_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/shared/app_logger.dart';
import 'package:shiori/shared/source_image.dart';
import '../test/data/local/support/epub_fixtures.dart';

T ok<T>(Result<T> r) => (r as Success<T>).value;
CancellationToken token() => CancellationSource().token;
void require(bool value) {
  if (!value) throw StateError('assertion');
}

class _Offline implements NovelRepository, ImageRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('online_called');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('ANDROID002_RUNNING'))),
    ),
  );
  final report = <String, Object?>{};
  var step = 'open';
  try {
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/android002-probe-v1');
    final paths = AppPaths(
      support: root,
      temporary: await getTemporaryDirectory(),
      environment: StorageEnvironment.development,
    );
    var db = ok(await LocalDatabases.open(paths));
    final marker = File('${root.path}/prepared');
    final cold = await marker.exists();
    report['cold'] = cold;
    final decoder = const BookDecoder();
    final inputs = [
      utf8.encode(
        '第一章 星光\n${List.generate(100, (i) => '自写离线段落 $i。读取用户库不会访问网络。').join('\n')}\n第二章 日出\n终章正文。',
      ),
      zipFiles(epubFiles()),
    ];
    final books = <LocalBookRecord>[];
    if (cold) {
      // ZIP timestamps are not stable across generation. Reuse exact originals
      // so this checks byte-identity deduplication, not a newly encoded ZIP.
      final index = ok(await db.localBooks.watchBooks().first);
      for (var i = 0; i < inputs.length; i++) {
        final format = i == 0 ? LocalBookFormat.txt : LocalBookFormat.epub;
        final book = index.firstWhere((b) => b.format == format);
        inputs[i] = await File(
          '${paths.localBooks.path}/${book.key.novelId}/original',
        ).readAsBytes();
      }
    }
    step = 'import';
    for (var i = 0; i < inputs.length; i++) {
      final format = i == 0 ? LocalBookFormat.txt : LocalBookFormat.epub;
      books.add(
        ok(
          await db.localBooks.importBook(
            bytes: Stream.value(inputs[i]),
            format: format,
            addToShelf: true,
            cancellation: token(),
            parse: (session) {
              if (cold) throw StateError('reparsed');
              return decoder.decode(
                session,
                format: format,
                filename: 'ANDROID002.${format.name}',
                cancellation: token(),
                chooseEncoding: (_) async => TxtEncoding.utf8,
              );
            },
          ),
        ),
      );
    }
    final library = LocalLibraryRepository(db.users);
    require(ok(await library.watchBookshelf().first).length == 2);
    step = 'settings_progress';
    final app = PreferencesAppSettingsStore(
      preferences: SharedPreferencesAsync(),
      paths: paths,
      logger: AppLogger(),
    );
    final reading = PreferencesSettingsStore(
      preferences: SharedPreferencesAsync(),
      paths: paths,
      logger: AppLogger(),
    );
    final chapter = books.first.content.chapters.first;
    if (!cold) {
      ok(
        await app.save(
          AppSettings(accent: AppAccent.blueGrey),
          cancellation: token(),
        ),
      );
      ok(
        await reading.save(
          ReaderSettings(mode: ReaderMode.scroll, controlsHintSeen: true),
          cancellation: token(),
        ),
      );
      final generation = ok(
        await library.beginProgressSession(
          chapter.key.novelKey,
          cancellation: token(),
        ),
      );
      ok(
        await library.saveProgress(
          ReadingProgress(
            snapshot: books.first.content.detail.summary,
            chapterKey: chapter.key,
            chapterOrdinalSnapshot: 0,
            catalogRevision: books.first.content.catalog.revision,
            position: ReaderPosition(
              contentRevision: chapter.contentRevision,
              blockKey: chapter.blocks[30].blockKey,
              blockIndex: 30,
              blockFraction: 0,
              chapterFraction: .3,
            ),
            completed: false,
            lastReadAt: DateTime.now(),
          ),
          stamp: ProgressWriteStamp(generation: generation, sequence: 0),
          cancellation: token(),
        ),
      );
    }
    require(
      ok(await app.load(cancellation: token())).accent == AppAccent.blueGrey,
    );
    require(
      ok(await reading.load(cancellation: token())).mode == ReaderMode.scroll,
    );
    require(
      ok(
            await library.getProgress(
              chapter.key.novelKey,
              cancellation: token(),
            ),
          ) !=
          null,
    );
    report['settings_progress'] = 'PASS';
    step = 'cache_isolation';
    final coordinator = CacheCoordinator();
    final source = FixtureNovelSource(scenario: FixtureScenario.twentyImages);
    final memory = MemoryImageRepository(
      resolve: (_) => source,
      logger: AppLogger(),
    );
    final images = PersistentImageRepository(
      network: memory,
      db: db.cache,
      paths: paths,
      coordinator: coordinator,
    );
    final records = NovelRecordStore(db.cache, coordinator: coordinator);
    final cached = source.data.content(FixtureScenario.twentyImages);
    ok(
      await records.writeChapter(
        cached,
        fetchedAt: DateTime.now(),
        parserVersion: 1,
        cancellation: token(),
      ),
    );
    final ref = cached.blocks.whereType<ImageBlock>().first.media;
    final lease = ok(
      await images.load(ref, mode: ReadMode.cacheFirst, cancellation: token()),
    ).value;
    require(lease.persistence == MediaPersistence.persistedLocal);
    await lease.close();
    final cache = LocalCacheManagement(db.cache, coordinator, images);
    ok(await cache.clear());
    require(ok(await cache.inspect()).chapters.isEmpty);
    require(ok(await library.watchBookshelf().first).length == 2);
    require(
      ok(
            await library.getProgress(
              chapter.key.novelKey,
              cancellation: token(),
            ),
          ) !=
          null,
    );
    await images.close();
    await coordinator.close();
    await db.close();
    db = ok(await LocalDatabases.open(paths));
    final novels = LocalReadingRepository(
      local: db.localBooks,
      online: _Offline(),
    );
    final localImages = LocalImageRepository(
      local: db.localBooks,
      online: _Offline(),
    );
    for (final book in books) {
      final key = book.content.detail.summary.key;
      require(
        ok(
          await novels.loadCatalog(
            key,
            mode: ReadMode.cacheOnly,
            cancellation: token(),
          ),
        ).value.flatChapters.isNotEmpty,
      );
      for (final chapter in book.content.chapters) {
        require(
          ok(
                await novels.loadChapter(
                  chapter.key,
                  mode: ReadMode.cacheOnly,
                  cancellation: token(),
                ),
              ).origin ==
              LoadOrigin.local,
        );
      }
    }
    final cover = books.last.content.detail.summary.cover!;
    final owned = ok(
      await localImages.load(
        cover,
        mode: ReadMode.cacheOnly,
        cancellation: token(),
      ),
    ).value;
    final decoded = await decodeSourceImage(owned.data, 64);
    require(decoded.image.width > 0);
    decoded.image.dispose();
    await owned.close();
    report['reopen_cache_clear_image_decode'] = 'PASS';
    step = 'disk_full';
    // Real SQLITE_FULL in a separate bounded DB; never fill the phone filesystem.
    final faults = AppPaths(
      support: Directory('${root.path}/faults'),
      temporary: root,
      environment: StorageEnvironment.development,
    );
    await faults.prepare();
    final faultDb = UserDatabase(NativeDatabase(faults.userDatabase));
    final faultStore = ok(await ManagedLocalBooks.open(faults, faultDb));
    final pages =
        (await faultDb.customSelect('PRAGMA page_count').getSingle())
                .data
                .values
                .single
            as int;
    await faultDb.customStatement('PRAGMA max_page_count=$pages');
    final failed = await faultStore.importBook(
      bytes: Stream.value(utf8.encode('fault fixture')),
      format: LocalBookFormat.txt,
      addToShelf: true,
      cancellation: token(),
      parse: (s) async {
        final key = LocalBookIdentity.chapter(s.key, 'test');
        final title = 'Bounded fixture ' * 30000;
        return LocalBookContent(
          detail: NovelDetail(
            summary: NovelSummary(key: s.key, title: title),
          ),
          catalog: Catalog(
            novelKey: s.key,
            volumes: [
              Volume(
                groupId: 'v',
                chapters: [
                  Chapter(
                    key: key,
                    title: 'chapter',
                    ordinal: 0,
                    volumeGroupId: 'v',
                  ),
                ],
              ),
            ],
          ),
          chapters: [
            ChapterContent(
              key: key,
              title: 'chapter',
              blocks: [ParagraphBlock(text: 'self authored')],
            ),
          ],
        );
      },
    );
    require(
      failed is Failure<LocalBookRecord> &&
          failed.failure.kind == FailureKind.database,
    );
    require(ok(await faultStore.watchBooks().first).isEmpty);
    require((await faults.localBooks.list().toList()).isEmpty);
    require(ok(await db.localBooks.watchBooks().first).length == 2);
    await faultStore.close();
    await faultDb.close();
    await Directory('${root.path}/faults').delete(recursive: true);
    report['bounded_sqlite_full_rollback'] = 'PASS';
    step = 'tls';
    if (const bool.fromEnvironment('ANDROID002_TLS')) {
      final once = File(
        '${root.path}/tls-${const String.fromEnvironment('ANDROID002_RUN', defaultValue: 'v1')}.started',
      );
      if (!await once.exists()) {
        await once.writeAsString('one-request', flush: true);
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        try {
          final status = await (() async {
            final req = await client.getUrl(Uri.parse('https://example.com/'));
            req.followRedirects = false;
            final response = await req.close();
            await response.take(1).drain<void>();
            return response.statusCode;
          })().timeout(const Duration(seconds: 15));
          report['tls'] = status == 200 ? 'PASS' : 'HTTP_$status';
        } catch (e) {
          report['tls'] = e.runtimeType.toString();
        } finally {
          client.close(force: true);
        }
      } else {
        report['tls'] = 'SKIPPED_ALREADY_ATTEMPTED';
      }
    }
    await marker.writeAsString('prepared', flush: true);
    report['status'] = 'PASS';
    debugPrint('ANDROID002_REPORT ${jsonEncode(report)}');
    await File(
      '${root.path}/report.json',
    ).writeAsString(jsonEncode(report), flush: true);
    runApp(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: chapter.key,
            repository: novels,
            library: LocalLibraryRepository(db.users),
            images: localImages,
            settings: reading,
          ),
        ),
      ),
    );
  } catch (e) {
    debugPrint(
      'ANDROID002_FAIL ${jsonEncode({'step': step, 'type': e.runtimeType.toString(), ...report})}',
    );
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Text('ANDROID002_FAIL $step ${e.runtimeType}')),
        ),
      ),
    );
  }
}
