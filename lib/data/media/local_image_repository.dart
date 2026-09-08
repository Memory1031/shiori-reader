import 'dart:typed_data';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';

/// Each load owns verified bytes. Deleting the book cannot invalidate an active
/// lease; new loads after deletion fail. No URL, online cache or network access.
class LocalImageRepository implements ImageRepository {
  LocalImageRepository({required this.local, required this.online});
  final LocalBookStore local;
  final ImageRepository online;
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    if (ref.sourceId != LocalBookIdentity.sourceId) {
      return online.load(ref, mode: mode, cancellation: cancellation);
    }
    final result = await local.readMedia(ref, cancellation: cancellation);
    if (result case Failure(:final failure)) return Failure(failure);
    final bytes = (result as Success<Uint8List>).value;
    final lease = _LocalLease(
      MemoryMedia(
        bytes: bytes,
        info: MediaInfo(format: MediaFormat.unknown, byteLength: bytes.length),
      ),
    );
    return Success(
      LoadResult<MediaLease>(
        value: lease,
        origin: LoadOrigin.local,
        fetchedAt: DateTime.now(),
      ),
    );
  }
}

class _LocalLease implements MediaLease {
  _LocalLease(this._data);
  MediaData? _data;
  @override
  MediaData get data => _data ?? (throw StateError('Closed media lease'));
  @override
  bool get isClosed => _data == null;
  @override
  MediaPersistence get persistence => MediaPersistence.persistedLocal;
  @override
  AppFailure? get persistenceFailure => null;
  @override
  Future<void> close() async {
    _data = null;
  }
}
