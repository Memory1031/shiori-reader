import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;
import '../data/cache/cache_policy.dart';
import '../data/cache/local_cache_management.dart';
import '../data/cache/reading_prefetch.dart';
import '../data/local/database/user_database.dart';
import '../data/local/files/app_paths.dart';
import '../data/media/persistent_image_repository.dart';
import '../data/local/database/cache_database.dart';
import '../data/media/memory_image_repository.dart';
import '../data/network/request_scheduler.dart';
import '../data/repositories/novel_repository.dart';
import '../data/sources/source_registry.dart';
import '../data/sources/lightnovel/lightnovel_source.dart';
import '../domain/contracts/contracts.dart';
import '../shared/app_logger.dart';

/// Explicit online composition. Construction performs no network I/O.
/// Caller owns cache and must close it after this bundle; no global registration.
final class SourceServices {
  SourceServices({
    required CacheDatabase cache,
    AppPaths? paths,
    UserDatabase? users,
    AppLogger? logger,
    HttpClientAdapter? adapter,
    HttpClientAdapter Function()? mediaAdapterFactory,
    Duration sourceInterval = const Duration(milliseconds: 500),
  }) {
    final diagnostics = logger ?? AppLogger();
    coordinator = CacheCoordinator();
    _scheduler = RequestScheduler(startInterval: sourceInterval);
    _source = LightNovelSource(
      scheduler: _scheduler,
      logger: diagnostics,
      adapter: adapter,
      mediaAdapterFactory: mediaAdapterFactory,
    );
    registry = SourceRegistry([_source]);
    novels = createNovelRepository(
      sources: registry,
      cache: cache,
      logger: diagnostics,
      coordinator: coordinator,
    );
    _memory = MemoryImageRepository(
      maxIdleBytes: 32 * 1024 * 1024,
      resolve: (id) {
        final source = registry[id];
        return source is SourceMedia ? source as SourceMedia : null;
      },
      logger: diagnostics,
    );
    if (paths != null) {
      _disk =
          PersistentImageRepository(
              network: _memory,
              db: cache,
              paths: paths,
              coordinator: coordinator,
            )
            ..validate = (bytes) async {
              final buffer = await ui.ImmutableBuffer.fromUint8List(
                Uint8List.fromList(bytes),
              );
              ui.ImageDescriptor? descriptor;
              try {
                descriptor = await ui.ImageDescriptor.encoded(buffer);
                if (descriptor.width > 32768 ||
                    descriptor.height > 32768 ||
                    descriptor.width * descriptor.height > 100000000) {
                  throw const FormatException('Image too large');
                }
                final codec = await descriptor.instantiateCodec(
                  targetWidth: 1,
                  targetHeight: 1,
                );
                try {
                  final frame = await codec.getNextFrame();
                  frame.image.dispose();
                } finally {
                  codec.dispose();
                }
              } finally {
                descriptor?.dispose();
                buffer.dispose();
              }
            };
      cacheManagement = LocalCacheManagement(cache, coordinator, _disk!);
      unawaited(_disk!.maintain().catchError((Object _) {}));
    }
    images = _disk ?? _memory;
    if (users != null && cacheManagement != null) {
      _prefetch = LocalReadingPrefetch(
        users: users,
        novels: novels,
        images: images,
        coordinator: coordinator,
      );
      cacheManagement!.prefetch = _prefetch;
    }
  }
  late final RequestScheduler _scheduler;
  late final LightNovelSource _source;
  late final SourceRegistry registry;
  late final DefaultNovelRepository novels;
  late final CacheCoordinator coordinator;
  late final MemoryImageRepository _memory;
  PersistentImageRepository? _disk;
  LocalCacheManagement? cacheManagement;
  LocalReadingPrefetch? _prefetch;
  late final ImageRepository images;
  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await _prefetch?.close();
    if (_disk != null) {
      await _disk!.close();
    } else {
      _memory.close();
    }
    await novels.close();
    _source.close();
    _scheduler.close();
    await coordinator.close();
  }
}
