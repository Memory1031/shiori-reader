import 'dart:typed_data';

import '../errors/app_failure.dart';
import '../models/models.dart';
import '../models/value_model.dart';
import 'cancellation.dart';
import 'loading.dart';
import 'result.dart';

enum MediaFormat { jpeg, png, webp, gif, avif, unknown }

enum MediaPersistence { memoryOnly, persistedLocal }

final class MediaInfo extends ValueModel {
  MediaInfo({required this.format, this.byteLength, this.width, this.height}) {
    if ([
      byteLength,
      width,
      height,
    ].any((value) => value != null && value <= 0)) {
      throw ArgumentError('Known media sizes must be positive');
    }
  }
  final MediaFormat format;
  final int? byteLength;
  final int? width;
  final int? height;
  @override
  List<Object?> get values => [format, byteLength, width, height];
}

/// Single-consumer stream. Success chunks are immutable, total <= maxBytes.
/// Expected read/limit/cancellation errors emit ONE terminal Failure chunk,
/// followed by done, never addError(rawException). close must be safe even when
/// never listened to, idempotent, and must release/abort the underlying request.
abstract interface class SourceMediaBody {
  MediaInfo get info;
  int get maxBytes;
  Stream<Result<List<int>>> get chunks;
  Future<void> close();
}

/// Implemented by the same object as NovelSource, independent of its UI client.
abstract interface class SourceMedia {
  Future<Result<SourceMediaBody>> openMedia(
    MediaRef ref, {
    required int maxBytes,
    required CancellationToken cancellation,
  });
}

sealed class MediaData {
  const MediaData(this.info);
  final MediaInfo info;
}

final class MemoryMedia extends MediaData {
  MemoryMedia({required Uint8List bytes, required MediaInfo info})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
      super(info) {
    if (bytes.isEmpty ||
        (info.byteLength != null && info.byteLength != bytes.length)) {
      throw ArgumentError('Media bytes must match declared size');
    }
  }
  final Uint8List bytes;
}

/// Validated app-private local file path. Never a remote URL; validation and
/// containment belong to CACHE-003. UI adapter may create File/ImageProvider.
final class LocalMedia extends MediaData {
  LocalMedia({required String path, required MediaInfo info})
    : path = nonBlank(path, 'localPath'),
      super(info);
  final String path;
}

/// One independently owned lease per successful load. close releases only this
/// consumer's pin/reference, not other readers' leases. No raw close errors;
/// implementation sends cleanup diagnostics to its private logger.
abstract interface class MediaLease {
  MediaData get data;
  MediaPersistence get persistence;
  AppFailure? get persistenceFailure;
  bool get isClosed;
  Future<void> close();
}

abstract interface class ImageRepository {
  /// cacheOnly never opens SourceMedia/session/network/prefetch. A Phase 4
  /// implementation may satisfy it from RAM; RAM is not persistedLocal.
  /// LocalMedia always requires persistedLocal; failed writes retain readable
  /// memory data with persistenceFailure, not a claim of offline availability.
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  });
}
