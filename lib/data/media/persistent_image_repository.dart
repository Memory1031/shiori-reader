import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../cache/cache_policy.dart';
import '../local/database/cache_database.dart';
import '../local/files/app_paths.dart';
import 'memory_image_repository.dart';
import '../network/background_work.dart';

/// File ownership and disk mutation are serialized; each returned file is pinned
/// until its independent lease closes. A refreshed version never overwrites it.
class PersistentImageRepository implements ImageRepository {
  PersistentImageRepository({
    required this.network,
    required this.db,
    required this.paths,
    required this.coordinator,
  });
  final MemoryImageRepository network;
  final CacheDatabase db;
  final AppPaths paths;
  final CacheCoordinator coordinator;
  static String keyFor(MediaRef ref) =>
      sha256.convert(utf8.encode(jsonEncode(ref.identityFields))).toString();
  bool _closed = false;
  int _serial = 0;
  final _work = <Future<void>>{};
  Future<void> Function(List<int>)? validate;
  final _access = <String, DateTime>{};
  StreamIterator<FileSystemEntity>? _sweep;
  Timer? _maintenanceTimer;
  Stream<FileSystemEntity> _files() async* {
    await _managedDirectory(paths.staging);
    await _managedDirectory(paths.images);
    yield* paths.staging.list(followLinks: false);
    yield* paths.images.list(followLinks: false);
  }

  void _scheduleMaintenance() {
    if (_closed || _maintenanceTimer != null) return;
    _maintenanceTimer = Timer(const Duration(seconds: 1), () {
      _maintenanceTimer = null;
      unawaited(maintain().catchError((Object _) {}));
    });
  }

  AppFailure _failure() => AppFailure(
    kind: FailureKind.cache,
    operation: Operation.media,
    context: FailureContext.cacheWriteFailed,
  );

  Future<String> _managedDirectory(Directory directory) async {
    final managed = await paths.root.resolveSymbolicLinks();
    final resolved = await directory.resolveSymbolicLinks();
    if (!p.isWithin(managed, resolved) ||
        await FileSystemEntity.isLink(directory.path)) {
      throw const FormatException('Invalid cache directory');
    }
    return resolved;
  }

  Future<File> _file(String name) async {
    if (!RegExp(r'^[a-f0-9]{64}-[a-f0-9]{64}\.img$').hasMatch(name)) {
      throw const FormatException('Invalid file identity');
    }
    final root = await _managedDirectory(paths.images);
    final file = File(p.join(root, name));
    if (!p.isWithin(root, file.absolute.path) ||
        await FileSystemEntity.isLink(file.path)) {
      throw const FormatException('Invalid cache path');
    }
    return file;
  }

  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    final future = _load(ref, mode, cancellation);
    final settled = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _work.add(settled);
    settled.whenComplete(() => _work.remove(settled));
    return future;
  }

  Future<Result<LoadResult<MediaLease>>> _load(
    MediaRef ref,
    ReadMode mode,
    CancellationToken token,
  ) async {
    if (_closed || token.isCancelled) {
      return Failure(AppFailure.cancelled(Operation.media));
    }
    final generation = coordinator.generation;
    LoadResult<MediaLease>? local;
    try {
      local = await coordinator.exclusive(() => _read(ref));
    } catch (_) {
      /* Corrupt local entries degrade to a miss. */
    }
    if (token.isCancelled || generation != coordinator.generation) {
      await local?.value.close();
      return Failure(AppFailure.cancelled(Operation.media));
    }
    if (local != null && mode != ReadMode.refresh) return Success(local);
    if (mode == ReadMode.cacheOnly) {
      return Failure(
        AppFailure(
          kind: FailureKind.cache,
          operation: Operation.media,
          context: FailureContext.cacheMiss,
        ),
      );
    }
    final remote = await network.load(ref, mode: mode, cancellation: token);
    if (_closed || token.isCancelled || generation != coordinator.generation) {
      await local?.value.close();
      if (remote case Success(:final value)) await value.value.close();
      return Failure(AppFailure.cancelled(Operation.media));
    }
    if (remote case Failure(:final failure)) {
      if (local != null && !failure.isCancellation) {
        return Success(
          LoadResult(
            value: local.value,
            origin: LoadOrigin.local,
            fetchedAt: local.fetchedAt,
            isStale: true,
            refreshFailure: failure,
          ),
        );
      }
      await local?.value.close();
      return Failure(failure);
    }
    final loaded = (remote as Success<LoadResult<MediaLease>>).value;
    final lease = loaded.value;
    if (loaded.isStale) {
      await local?.value.close();
      return Success(loaded);
    }
    final data = lease.data as MemoryMedia;
    try {
      await validate?.call(data.bytes);
      final persisted = await coordinator.exclusive(() async {
        if (generation != coordinator.generation ||
            token.isCancelled ||
            _closed) {
          return null;
        }
        final checksum = sha256.convert(data.bytes).toString();
        final key = keyFor(ref);
        final name = '$key-$checksum.img';
        final destination = await _file(name);
        if (BackgroundWork.current != null &&
            !BackgroundWork.current!.promoted) {
          final total = await db
              .customSelect(
                'SELECT COALESCE(SUM(byte_size),0) AS total FROM image_cache',
              )
              .getSingle();
          if (total.read<int>('total') + data.bytes.length >
              coordinator.policy.imageBytes) {
            throw const FileSystemException(
              'Background cache capacity reached',
            );
          }
        }
        // Staging is a private sibling on the same filesystem; never source-named.
        final staging = File(
          p.join(
            await _managedDirectory(paths.staging),
            '$key-${_serial++}.part',
          ),
        );
        try {
          if (await destination.exists()) {
            final valid =
                await destination.length() == data.bytes.length &&
                (await sha256.bind(destination.openRead()).first).toString() ==
                    checksum;
            if (!valid) {
              // Never overwrite bytes owned by a live lease. A corrupt idle
              // version can be replaced atomically by its verified payload.
              if (coordinator.isPinned(destination.path)) {
                throw const FileSystemException('Corrupt cache is in use');
              }
              await destination.delete();
            }
          }
          if (!await destination.exists()) {
            await staging.writeAsBytes(data.bytes, flush: true);
            if (generation != coordinator.generation || token.isCancelled) {
              return null;
            }
            await staging.rename(destination.path);
          }
          final time = coordinator.now().millisecondsSinceEpoch;
          if (generation != coordinator.generation || token.isCancelled) {
            return null;
          }
          await db.customStatement(
            'INSERT INTO image_cache(cache_key,ref_json,file_name,checksum,byte_size,format,fetched_at,last_access_at) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(cache_key) DO UPDATE SET file_name=excluded.file_name,checksum=excluded.checksum,byte_size=excluded.byte_size,format=excluded.format,fetched_at=excluded.fetched_at,last_access_at=excluded.last_access_at',
            [
              key,
              jsonEncode(ref.toJson()),
              name,
              checksum,
              data.bytes.length,
              data.info.format.name,
              time,
              time,
            ],
          );
          final result = _lease(
            destination,
            data.info,
            DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
          );
          try {
            await _evict();
          } catch (_) {
            await result.value.close();
            rethrow;
          }
          return result;
        } finally {
          if (await staging.exists()) await staging.delete();
        }
      });
      await local?.value.close();
      if (persisted == null) {
        await lease.close();
        return Failure(AppFailure.cancelled(Operation.media));
      }
      await lease.close();
      return Success(persisted);
    } catch (_) {
      await local?.value.close();
      if (generation != coordinator.generation ||
          token.isCancelled ||
          _closed) {
        await lease.close();
        return Failure(AppFailure.cancelled(Operation.media));
      }
      // Network success is still readable, but does not imply persistence.
      return Success(
        LoadResult(
          value: _MemoryFallback(lease, _failure()),
          origin: loaded.origin,
          fetchedAt: loaded.fetchedAt,
        ),
      );
    }
  }

  Future<LoadResult<MediaLease>?> _read(MediaRef ref) async {
    final key = keyFor(ref);
    final row = await db
        .customSelect(
          'SELECT * FROM image_cache WHERE cache_key=?',
          variables: [Variable(key)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    try {
      final file = await _file(row.read<String>('file_name'));
      final size = row.read<int>('byte_size');
      if (size > network.maxBytes || await file.length() != size) {
        throw const FormatException('Invalid length');
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != row.read<String>('checksum')) {
        throw const FormatException('Invalid checksum');
      }
      final time = coordinator.now();
      if (time.difference(_access[key] ?? DateTime(1970)) >=
          const Duration(minutes: 1)) {
        _access[key] = time;
        if (_access.length > 1024) _access.remove(_access.keys.first);
        try {
          await db.customStatement(
            'UPDATE image_cache SET last_access_at=? WHERE cache_key=?',
            [time.millisecondsSinceEpoch, key],
          );
        } catch (_) {
          /* Readable files survive read-only metadata. */
        }
      }
      return _lease(
        file,
        MediaInfo(
          format: MediaFormat.values.byName(row.read<String>('format')),
          byteLength: size,
        ),
        DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('fetched_at'),
          isUtc: true,
        ),
      );
    } catch (_) {
      await db.customStatement('DELETE FROM image_cache WHERE cache_key=?', [
        key,
      ]);
      return null;
    }
  }

  LoadResult<MediaLease> _lease(File file, MediaInfo info, DateTime time) {
    final release = coordinator.pin(file.path);
    return LoadResult(
      value: _FileLease(LocalMedia(path: file.path, info: info), () {
        release();
        _scheduleMaintenance();
      }),
      origin: LoadOrigin.local,
      fetchedAt: time,
    );
  }

  Future<void> _evict() async {
    final rows = await db
        .customSelect(
          'SELECT cache_key,file_name,byte_size FROM image_cache ORDER BY last_access_at',
        )
        .get();
    var total = rows.fold<int>(0, (sum, r) => sum + r.read<int>('byte_size'));
    if (total <= coordinator.policy.imageBytes) return;
    for (final row in rows) {
      if (total <= coordinator.policy.target(coordinator.policy.imageBytes)) {
        break;
      }
      File file;
      try {
        file = await _file(row.read<String>('file_name'));
      } on FormatException {
        await db.customStatement('DELETE FROM image_cache WHERE cache_key=?', [
          row.read<String>('cache_key'),
        ]);
        total -= row.read<int>('byte_size');
        continue;
      }
      if (coordinator.isPinned(file.path)) continue;
      await db.customStatement('DELETE FROM image_cache WHERE cache_key=?', [
        row.read<String>('cache_key'),
      ]);
      if (await file.exists()) await file.delete();
      total -= row.read<int>('byte_size');
    }
  }

  /// Bounded maintenance never scans/decodes every image at launch.
  Future<void> maintain() => coordinator.exclusive(() async {
    if (_closed) return;
    await _evict();
    final sweep = _sweep ??= StreamIterator(_files());
    for (var visited = 0; visited < 128; visited++) {
      if (!await sweep.moveNext()) {
        await sweep.cancel();
        _sweep = null;
        return;
      }
      final entity = sweep.current;
      if (entity is! File) continue;
      // Leases use canonical paths. macOS temporary roots may be reached via
      // /var while their canonical identity starts with /private/var.
      final identity = await entity.resolveSymbolicLinks();
      if (coordinator.isPinned(identity)) continue;
      if (p.dirname(entity.path) == paths.staging.path) {
        await entity.delete();
        continue;
      }
      final name = p.basename(entity.path);
      final row = await db
          .customSelect(
            'SELECT 1 FROM image_cache WHERE file_name=?',
            variables: [Variable(name)],
          )
          .getSingleOrNull();
      if (row == null) await entity.delete();
    }
    _scheduleMaintenance();
  });
  Future<void> close() async {
    _closed = true;
    _maintenanceTimer?.cancel();
    network.close();
    await Future.wait(_work.toList());
    await coordinator.exclusive(() async {
      await _sweep?.cancel();
      _sweep = null;
    });
  }
}

class _FileLease implements MediaLease {
  _FileLease(this.data, this._release);
  @override
  final LocalMedia data;
  final void Function() _release;
  @override
  bool isClosed = false;
  @override
  MediaPersistence get persistence => MediaPersistence.persistedLocal;
  @override
  AppFailure? get persistenceFailure => null;
  @override
  Future<void> close() async {
    if (!isClosed) {
      isClosed = true;
      _release();
    }
  }
}

class _MemoryFallback implements MediaLease {
  _MemoryFallback(this.inner, this.persistenceFailure);
  final MediaLease inner;
  @override
  final AppFailure persistenceFailure;
  @override
  MediaData get data => inner.data;
  @override
  MediaPersistence get persistence => MediaPersistence.memoryOnly;
  @override
  bool get isClosed => inner.isClosed;
  @override
  Future<void> close() => inner.close();
}
