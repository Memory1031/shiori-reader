// TEST-004 explicit Android entry; all HTTP is synthetic and storage isolated.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/data/cache/cache_policy.dart';
import 'package:shiori/data/cache/local_cache_management.dart';
import 'package:shiori/data/local/database/local_databases.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/data/media/persistent_image_repository.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/novel_repository.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_source.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_identity.dart';
import 'package:shiori/data/sources/source_registry.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/dev/viewport/reader_viewport.dart';
import 'package:shiori/shared/app_logger.dart';
import 'support/mvp_fixture.dart';
import 'package:shiori/shared/source_image.dart';

T value<T>(Result<T> result) => (result as Success<T>).value;
Map<String, Object?>? position(ReaderPosition? p) => p == null
    ? null
    : {
        'revision': p.contentRevision,
        'blockKey': p.blockKey,
        'index': p.blockIndex,
        'fraction': p.blockFraction,
      };
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Directory(
    '${(await getApplicationSupportDirectory()).path}/test004',
  );
  final paths = AppPaths(
    support: root,
    temporary: root,
    environment: StorageEnvironment.development,
  );
  final db = value(await LocalDatabases.open(paths));
  final fixture = MvpFixture()
    ..offline = await File('${root.path}/offline').exists();
  final owner = CacheCoordinator();
  final scheduler = RequestScheduler(startInterval: Duration.zero);
  final source = LightNovelSource(
    scheduler: scheduler,
    logger: AppLogger(),
    adapter: fixture,
    mediaAdapterFactory: () => fixture,
  );
  final novels = createNovelRepository(
    sources: SourceRegistry([source]),
    cache: db.cache,
    coordinator: owner,
    now: () => DateTime.utc(2026, 9, 8),
  );
  final images = PersistentImageRepository(
    network: MemoryImageRepository(resolve: (_) => source),
    db: db.cache,
    paths: paths,
    coordinator: owner,
  );
  final library = LocalLibraryRepository(db.users);
  final settings = FixtureSettingsStore();
  await settings.save(
    ReaderSettings(mode: ReaderMode.scroll, controlsHintSeen: true),
    cancellation: CancellationSource().token,
  );
  final initial = value(
    await library.getProgress(
      lightNovelKey(1),
      cancellation: CancellationSource().token,
    ),
  );
  final errors = <String>[];
  final previousError = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    previousError?.call(details);
  };
  runApp(
    ShioriApp(
      locale: const Locale('en'),
      homeBuilder: (_, app) => ReadingHome(
        repository: novels,
        library: library,
        sources: [source.descriptor],
        images: images,
        cache: LocalCacheManagement(db.cache, owner, images),
        settings: settings,
        environmentLabel: 'Offline fixture',
      ),
    ),
  );
  var busy = false;
  Timer.periodic(const Duration(milliseconds: 400), (_) async {
    if (busy) return;
    busy = true;
    try {
      var reading = false, decoded = 0;
      ReaderPosition? current;
      final decodedMedia = <String>{};
      void visit(Element e) {
        if (e.widget case Offstage(offstage: true)) return;
        if (e.widget case SourceImage(:final media)) {
          void imageNode(Element node) {
            if (node.widget case RawImage(:final image?)) {
              if (image.width > 0) decodedMedia.add(media.mediaId);
            }
            node.visitChildren(imageNode);
          }

          e.visitChildren(imageNode);
        }
        if (e.widget is ReaderContentView) reading = true;
        if (e.widget case RawImage(:final image?)) {
          if (image.width > 0) decoded++;
        }
        if (e.widget case ReaderViewport(:final controller)) {
          current = controller.capture();
        }
        e.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(visit);
      final saved = value(
        await library.getProgress(
          lightNovelKey(1),
          cancellation: CancellationSource().token,
        ),
      );
      final report = {
        'offline': fixture.offline,
        'calls': fixture.calls,
        'stages': fixture.stages,
        'shelfCount':
            (await db.users.customSelect('SELECT * FROM bookshelf').get())
                .length,
        'reading': reading,
        'decoded': decoded,
        'decodedMedia': decodedMedia.toList(),
        'current': position(current),
        'saved': position(saved?.position),
        'initialSaved': position(initial?.position),
        'errors': errors,
      };
      final temporary = File('${root.path}/status.tmp');
      await temporary.writeAsString(jsonEncode(report));
      await temporary.rename('${root.path}/status.json');
    } finally {
      busy = false;
    }
  });
  // Process lifetime owns these resources. The runner uses Android force-stop
  // to verify persistence without relying on Dart dispose or simulated reopen.
}
