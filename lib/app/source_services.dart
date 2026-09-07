import 'package:dio/dio.dart';
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
    AppLogger? logger,
    HttpClientAdapter? adapter,
    HttpClientAdapter Function()? mediaAdapterFactory,
    Duration sourceInterval = const Duration(milliseconds: 500),
  }) {
    final diagnostics = logger ?? AppLogger();
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
    );
    images = MemoryImageRepository(
      maxIdleBytes: 32 * 1024 * 1024,
      resolve: (id) {
        final source = registry[id];
        return source is SourceMedia ? source as SourceMedia : null;
      },
      logger: diagnostics,
    );
  }
  late final RequestScheduler _scheduler;
  late final LightNovelSource _source;
  late final SourceRegistry registry;
  late final DefaultNovelRepository novels;
  late final MemoryImageRepository images;
  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    images.close();
    await novels.close();
    _source.close();
    _scheduler.close();
  }
}
