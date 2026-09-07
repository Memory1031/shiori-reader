import 'dart:async';
import '../network/background_work.dart';
import 'dart:typed_data';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/app_logger.dart';
import '../network/network_types.dart';

/// Encoded RAM data with optional bounded idle LRU. No disk/offline guarantee.
/// Real SourceMedia adapters must use the shared NetworkClient scheduler.
class MemoryImageRepository implements ImageRepository {
  MemoryImageRepository({
    required this.resolve,
    AppLogger? logger,
    DateTime Function()? now,
    this.maxBytes = 20 * 1024 * 1024,
    this.maxRetainedBytes = 64 * 1024 * 1024,
    this.maxIdleBytes = 0,
    this.deadline = const Duration(seconds: 45),
  }) : logger = logger ?? AppLogger(),
       now = now ?? DateTime.now {
    if (maxBytes < 1 ||
        maxBytes > 20 * 1024 * 1024 ||
        maxRetainedBytes < maxBytes ||
        maxIdleBytes < 0 ||
        maxIdleBytes > maxRetainedBytes ||
        deadline <= Duration.zero ||
        deadline > const Duration(seconds: 45)) {
      throw ArgumentError('Invalid media budget');
    }
  }
  final SourceMedia? Function(SourceId) resolve;
  final AppLogger logger;
  final DateTime Function() now;
  final int maxBytes;
  final int maxRetainedBytes;
  final int maxIdleBytes;
  final _idle = <MediaRef, _Entry>{};
  final Duration deadline;
  final _entries = <MediaRef, _Entry>{};
  final _retained = <_Entry>{};
  final _flights = <MediaRef, _Flight>{};
  int _running = 0;
  int _reserved = 0;
  bool _closed = false;
  int get retainedBytes =>
      _retained.fold(0, (sum, entry) => sum + entry.data.bytes.length);
  int get pendingCount => _flights.length;

  /// Drop lookup visibility after an explicit clear; existing leases stay valid.
  void invalidate() {
    for (final flight in _flights.values.toList()) {
      _abort(flight, AppFailure.cancelled(Operation.media));
    }
    _entries.clear();
    _idle.clear();
    _retained.removeWhere((entry) => entry.references == 0);
  }

  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) {
    if (_closed) throw StateError('ImageRepository closed');
    if (cancellation.isCancelled) {
      return Future.value(Failure(AppFailure.cancelled(Operation.media)));
    }
    final cached = _entries[ref];
    if (mode != ReadMode.refresh && cached != null) {
      return Future.value(Success(_lease(ref, cached, LoadOrigin.memory)));
    }
    if (mode == ReadMode.cacheOnly) {
      return Future.value(
        Failure(
          AppFailure(
            kind: FailureKind.cache,
            operation: Operation.media,
            context: FailureContext.cacheMiss,
          ),
        ),
      );
    }
    var flight = _flights[ref];
    if (flight == null) {
      if (_flights.length >= 20) {
        return Future.value(
          Failure(
            networkFailure(Operation.media, FailureKind.sourceUnavailable),
          ),
        );
      }
      flight = _Flight(ref);
      _flights[ref] = flight;
      final owned = flight;
      owned.timer = Timer(
        deadline,
        () =>
            _abort(owned, networkFailure(Operation.media, FailureKind.timeout)),
      );
    }
    final owner = flight;
    BackgroundWork.promote(owner.scope);
    final waiter = _Waiter(cancellation);
    owner.waiters.add(waiter);
    waiter.subscription = cancellation.whenCancelled.asStream().listen((_) {
      owner.waiters.remove(waiter);
      waiter.complete(Failure(AppFailure.cancelled(Operation.media)));
      if (owner.waiters.isEmpty) {
        _abort(owner, AppFailure.cancelled(Operation.media));
      }
    });
    _pump();
    return waiter.result.future;
  }

  void _pump() {
    if (_closed) return;
    for (final flight in _flights.values.toList()) {
      if (flight.started || flight.cancel.token.isCancelled) continue;
      _trimIdle(maxRetainedBytes - _reserved - maxBytes);
      if (_running >= 2 ||
          retainedBytes + _reserved + maxBytes > maxRetainedBytes) {
        break;
      }
      flight.started = true;
      _running++;
      _reserved += maxBytes;
      unawaited(flight.zone.run(() => _fetch(flight)));
    }
  }

  void _abort(_Flight flight, AppFailure failure) {
    flight.cancel.cancel();
    _finish(flight, Failure(failure));
    if (flight.body != null) _closeBody(flight);
  }

  Future<void> _fetch(_Flight flight) async {
    final stop = Completer<Result<MemoryMedia>>();
    final sub = flight.cancel.token.whenCancelled.asStream().listen((_) {
      if (!stop.isCompleted) {
        stop.complete(Failure(AppFailure.cancelled(Operation.media)));
      }
    });
    Future<Result<MemoryMedia>> read() async {
      try {
        final source = resolve(flight.ref.sourceId);
        if (source == null) {
          return Failure(
            AppFailure(
              kind: FailureKind.sourceUnavailable,
              operation: Operation.media,
              context: FailureContext.sourceMissing,
            ),
          );
        }
        final opened = await source.openMedia(
          flight.ref,
          maxBytes: maxBytes,
          cancellation: flight.cancel.token,
        );
        if (opened case Failure(:final failure)) return Failure(failure);
        final body = (opened as Success<SourceMediaBody>).value;
        flight.body = body;
        if (flight.cancel.token.isCancelled) {
          _closeBody(flight);
          return Failure(AppFailure.cancelled(Operation.media));
        }
        if (body.info.format == MediaFormat.unknown) {
          return Failure(
            networkFailure(Operation.media, FailureKind.unsupported),
          );
        }
        if ((body.info.byteLength ?? 0) > maxBytes) {
          return Failure(networkFailure(Operation.media, FailureKind.tooLarge));
        }
        final bytes = BytesBuilder(copy: false);
        final done = Completer<Result<MemoryMedia>>();
        flight.stream = body.chunks.listen(
          (chunk) {
            if (done.isCompleted || flight.cancel.token.isCancelled) return;
            switch (chunk) {
              case Failure(:final failure):
                done.complete(Failure(failure));
              case Success(:final value):
                if (bytes.length + value.length > maxBytes) {
                  done.complete(
                    Failure(
                      networkFailure(Operation.media, FailureKind.tooLarge),
                    ),
                  );
                } else {
                  bytes.add(Uint8List.fromList(value));
                }
            }
          },
          onError: (Object _) {
            if (!done.isCompleted) {
              done.complete(
                Failure(networkFailure(Operation.media, FailureKind.network)),
              );
            }
          },
          onDone: () {
            if (done.isCompleted) return;
            final data = bytes.takeBytes();
            if (data.isEmpty ||
                (body.info.byteLength != null &&
                    body.info.byteLength != data.length) ||
                _format(data) != body.info.format) {
              done.complete(
                Failure(networkFailure(Operation.media, FailureKind.parse)),
              );
            } else {
              done.complete(
                Success(
                  MemoryMedia(
                    bytes: data,
                    info: MediaInfo(
                      format: body.info.format,
                      byteLength: data.length,
                      width: body.info.width,
                      height: body.info.height,
                    ),
                  ),
                ),
              );
            }
          },
        );
        return await Future.any([done.future, stop.future]);
      } catch (_) {
        return Failure(networkFailure(Operation.media, FailureKind.network));
      }
    }

    try {
      final result = await Future.any([read(), stop.future]);
      if (!flight.cancel.token.isCancelled) _finish(flight, result);
    } finally {
      unawaited(sub.cancel());
      _closeBody(flight);
      _running--;
      _reserved -= maxBytes;
      _pump();
    }
  }

  void _closeBody(_Flight flight) {
    final stream = flight.stream;
    flight.stream = null;
    if (stream != null) unawaited(stream.cancel().catchError((Object _) {}));
    final body = flight.body;
    flight.body = null;
    if (body == null) return;
    try {
      unawaited(
        body.close().catchError((Object _) {
          logger.network(
            source: flight.ref.sourceId,
            operation: Operation.media,
            requestId: logger.newRequestId(),
            duration: Duration.zero,
            failure: networkFailure(Operation.media, FailureKind.network),
          );
        }),
      );
    } catch (_) {
      /* Never leak raw cleanup errors. */
    }
  }

  void _finish(_Flight flight, Result<MemoryMedia> result) {
    if (_flights[flight.ref] != flight) return;
    _flights.remove(flight.ref);
    flight.timer?.cancel();
    final old = _entries[flight.ref];
    _Entry? entry;
    if (result case Success(:final value)) {
      if (old != null && old.references == 0) {
        _idle.remove(flight.ref);
        _retained.remove(old);
      }
      entry = _Entry(value, now());
      _entries[flight.ref] = entry;
      _retained.add(entry);
    }
    for (final waiter in flight.waiters) {
      if (waiter.cancellation.isCancelled) {
        waiter.complete(Failure(AppFailure.cancelled(Operation.media)));
      } else if (entry != null) {
        waiter.complete(Success(_lease(flight.ref, entry, LoadOrigin.remote)));
      } else {
        final failure = (result as Failure<MemoryMedia>).failure;
        if (old != null && !failure.isCancellation) {
          old.refreshFailure = failure;
          waiter.complete(
            Success(
              _lease(flight.ref, old, LoadOrigin.memory, failure: failure),
            ),
          );
        } else {
          waiter.complete(Failure(failure));
        }
      }
    }
    flight.waiters.clear();
    if (entry != null && entry.references == 0) _release(flight.ref, entry);
  }

  LoadResult<MediaLease> _lease(
    MediaRef ref,
    _Entry entry,
    LoadOrigin origin, {
    AppFailure? failure,
  }) {
    _idle.remove(ref);
    entry.references++;
    final observedFailure = failure ?? entry.refreshFailure;
    return LoadResult(
      value: _Lease(entry.data, () => _release(ref, entry)),
      origin: origin,
      fetchedAt: entry.fetchedAt,
      isStale: observedFailure != null,
      refreshFailure: observedFailure,
    );
  }

  void _release(MediaRef ref, _Entry entry) {
    if (entry.references > 0) entry.references--;
    if (entry.references != 0) return;
    if (!_closed && _entries[ref] == entry && maxIdleBytes > 0) {
      _idle.remove(ref);
      _idle[ref] = entry;
      while (_idle.values.fold<int>(0, (sum, e) => sum + e.data.bytes.length) >
          maxIdleBytes) {
        _evictOldest();
      }
      _pump();
      return;
    }
    if (_entries[ref] == entry) _entries.remove(ref);
    _retained.remove(entry);
    _pump();
  }

  void _evictOldest() {
    final key = _idle.keys.first;
    final entry = _idle.remove(key)!;
    if (_entries[key] == entry) _entries.remove(key);
    _retained.remove(entry);
  }

  void _trimIdle(int target) {
    while (_idle.isNotEmpty && retainedBytes > target) {
      _evictOldest();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final flight in _flights.values.toList()) {
      _abort(flight, AppFailure.cancelled(Operation.media));
    }
    _entries.clear();
    _idle.clear();
    _retained.removeWhere((entry) => entry.references == 0);
    // Outstanding leases still own their data until they independently close.
  }
}

class _Entry {
  _Entry(this.data, this.fetchedAt);
  final MemoryMedia data;
  final DateTime fetchedAt;
  int references = 0;
  AppFailure? refreshFailure;
}

class _Flight {
  _Flight(this.ref);
  final zone = Zone.current;
  final scope = BackgroundWork.current;
  final MediaRef ref;
  final cancel = CancellationSource();
  final waiters = <_Waiter>{};
  bool started = false;
  Timer? timer;
  SourceMediaBody? body;
  StreamSubscription<Result<List<int>>>? stream;
}

class _Waiter {
  _Waiter(this.cancellation);
  final CancellationToken cancellation;
  final result = Completer<Result<LoadResult<MediaLease>>>();
  StreamSubscription<void>? subscription;
  void complete(Result<LoadResult<MediaLease>> value) {
    if (result.isCompleted) return;
    unawaited(subscription?.cancel());
    result.complete(value);
  }
}

class _Lease implements MediaLease {
  _Lease(this.data, this.release);
  @override
  final MemoryMedia data;
  final void Function() release;
  @override
  bool isClosed = false;
  @override
  MediaPersistence get persistence => MediaPersistence.memoryOnly;
  @override
  AppFailure? get persistenceFailure => null;
  @override
  Future<void> close() async {
    if (isClosed) return;
    isClosed = true;
    release();
  }
}

MediaFormat _format(Uint8List bytes) {
  bool prefix(List<int> value) =>
      bytes.length >= value.length &&
      List.generate(value.length, (i) => bytes[i] == value[i]).every((v) => v);
  if (prefix([137, 80, 78, 71, 13, 10, 26, 10])) return MediaFormat.png;
  if (prefix([255, 216, 255])) return MediaFormat.jpeg;
  if (prefix([71, 73, 70, 56, 55, 97]) || prefix([71, 73, 70, 56, 57, 97])) {
    return MediaFormat.gif;
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return MediaFormat.webp;
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.skip(4).take(4)) == 'ftyp' &&
      {'avif', 'avis'}.contains(String.fromCharCodes(bytes.skip(8).take(4)))) {
    return MediaFormat.avif;
  }
  return MediaFormat.unknown;
}
