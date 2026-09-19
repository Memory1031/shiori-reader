// Offline fixture-only Android cold-process check; never imports a live Source.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/cache/cache_policy.dart';
import 'package:shiori/data/cache/local_cache_management.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/data/media/persistent_image_repository.dart';
import 'package:shiori/data/repositories/novel_repository.dart';
import 'package:shiori/data/sources/source_registry.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/shared/source_image.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ShioriApp(
      locale: const Locale('en'),
      routes: AppRoutes(home: (_) => const _Probe()),
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  String status = 'CACHE_START';
  Widget? reader;
  void report(String message) {
    debugPrint(message);
    if (mounted) setState(() => status = message);
  }

  @override
  void initState() {
    super.initState();
    unawaited(run());
  }

  Future<void> run() async {
    try {
      final support = await getApplicationSupportDirectory();
      final paths = AppPaths(
        support: Directory('${support.path}/phase6-cache-probe'),
        temporary: await getTemporaryDirectory(),
        environment: StorageEnvironment.development,
      );
      final db =
          (await LocalDatabases.open(paths) as Success<LocalDatabases>).value;
      final coordinator = CacheCoordinator();
      final fixture = FixtureNovelSource(
        scenario: FixtureScenario.twentyImages,
      );
      final marker = File('${paths.root.path}/prepared');
      final cold = await marker.exists();
      var misses = 0;
      final memory = MemoryImageRepository(
        resolve: (_) {
          if (cold) {
            misses++;
            throw StateError('Unexpected offline Source call');
          }
          return fixture;
        },
      );
      final images = PersistentImageRepository(
        network: memory,
        db: db.cache,
        paths: paths,
        coordinator: coordinator,
      );
      images.validate = (bytes) async {
        final decoded = await decodeSourceImage(
          MemoryMedia(
            bytes: Uint8List.fromList(bytes),
            info: MediaInfo(format: MediaFormat.png, byteLength: bytes.length),
          ),
          64,
        );
        decoded.image.dispose();
      };
      final novel = fixtureNovelKey(FixtureScenario.twentyImages);
      final chapter = fixture.data.content(FixtureScenario.twentyImages);
      final refs = chapter.blocks
          .whereType<ImageBlock>()
          .map((b) => b.media)
          .toList();
      final token = CancellationSource().token;
      if (!cold) {
        final records = NovelRecordStore(db.cache, coordinator: coordinator);
        await records.writeDetail(
          fixture.data.detail(FixtureScenario.twentyImages),
          fetchedAt: DateTime.now(),
          parserVersion: 1,
          cancellation: token,
        );
        await records.writeCatalog(
          fixture.data.catalog(FixtureScenario.twentyImages),
          fetchedAt: DateTime.now(),
          parserVersion: 1,
          cancellation: token,
        );
        await records.writeChapter(
          chapter,
          fetchedAt: DateTime.now(),
          parserVersion: 1,
          cancellation: token,
        );
        for (final ref in refs.take(19)) {
          final loaded = await images.load(
            ref,
            mode: ReadMode.cacheFirst,
            cancellation: token,
          );
          if (loaded is! Success<LoadResult<MediaLease>> ||
              loaded.value.value.persistence !=
                  MediaPersistence.persistedLocal) {
            throw StateError('Fixture persistence failed');
          }
          await loaded.value.value.close();
        }
        await marker.writeAsString('fixture-only', flush: true);
      }
      final cache = LocalCacheManagement(db.cache, coordinator, images);
      final overview =
          (await cache.inspect(novel: novel) as Success<CacheOverview>).value;
      if (overview.chapters.single.savedImages != 19 ||
          overview.chapters.single.imageCount != 20) {
        throw StateError('Wrong offline completeness');
      }
      final missing = await images.load(
        refs.last,
        mode: ReadMode.cacheOnly,
        cancellation: token,
      );
      if (missing is! Failure || misses != 0) {
        throw StateError('Offline miss requested Source');
      }
      final repo = createNovelRepository(
        sources: SourceRegistry([]),
        cache: db.cache,
        coordinator: coordinator,
      );
      final loaded = await repo.loadChapter(
        chapter.key,
        mode: ReadMode.cacheOnly,
        cancellation: token,
      );
      if (loaded is! Success) throw StateError('Offline text unavailable');
      report(
        cold
            ? 'CACHE_COLD_19_OF_20_ZERO_SOURCE_PASS'
            : 'CACHE_PREPARED_19_OF_20_PASS',
      );
      if (!mounted) return;
      setState(
        () => reader = BookReaderScreen(
          chapter: chapter.key,
          repository: repo,
          images: images,
          cache: cache,
          offline: true,
        ),
      );
      for (var attempt = 0; attempt < 30; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        var rendered = false;
        void visit(Element element) {
          final widget = element.widget;
          if (widget is RawImage && widget.image != null) rendered = true;
          element.visitChildren(visit);
        }

        (context as Element).visitChildren(visit);
        if (rendered) {
          report(
            cold
                ? 'CACHE_COLD_READER_IMAGE_MOUNT_PASS'
                : 'CACHE_READER_IMAGE_MOUNT_PASS',
          );
          return;
        }
      }
      throw StateError('Reader did not mount decoded image');
    } catch (error) {
      report('CACHE_FAIL ${error.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        SafeArea(bottom: false, child: Text(status)),
        Expanded(child: reader ?? const SizedBox()),
      ],
    ),
  );
}
