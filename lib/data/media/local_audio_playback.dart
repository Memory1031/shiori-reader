import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart' as ap;
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';

/// Platform boundary kept injectable so cancellation and cleanup are testable.
abstract interface class AudioDevice {
  Stream<AudioPlaybackState> get states;
  Future<void> open(String path);
  Future<void> resume();
  Future<void> pause();
  Future<void> stop();
  Future<void> close();
}

class NativeAudioDevice implements AudioDevice {
  final _player = ap.AudioPlayer();
  @override
  Stream<AudioPlaybackState> get states => _player.onPlayerStateChanged.map(
    (s) => switch (s) {
      ap.PlayerState.playing => AudioPlaybackState.playing,
      ap.PlayerState.paused => AudioPlaybackState.paused,
      ap.PlayerState.completed => AudioPlaybackState.completed,
      _ => AudioPlaybackState.stopped,
    },
  );
  @override
  Future<void> open(String path) async {
    await _player.setReleaseMode(ap.ReleaseMode.stop);
    await _player.setSource(ap.DeviceFileSource(path));
  }

  @override
  Future<void> resume() => _player.resume();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> close() => _player.dispose();
}

/// Loads verified app-private book bytes, never a URL. A temporary copy remains
/// owned until the player stops, independently of book deletion or reparse.
class LocalAudioPlayback implements AudioPlayback {
  LocalAudioPlayback(
    this.books, {
    AudioDevice Function()? createDevice,
    Future<Directory> Function()? createDirectory,
  }) : _createDevice = createDevice ?? NativeAudioDevice.new,
       _createDirectory =
           createDirectory ??
           (() => Directory.systemTemp.createTemp('shiori-audio-'));
  final LocalBookStore books;
  final AudioDevice Function() _createDevice;
  final Future<Directory> Function() _createDirectory;
  final _states = StreamController<AudioPlaybackState>.broadcast();
  AudioDevice? _device;
  StreamSubscription<AudioPlaybackState>? _subscription;
  Directory? _directory;
  CancellationSource? _cancellation;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  var _generation = 0, _closed = false;
  @override
  Stream<AudioPlaybackState> get states => _states.stream;
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Result<void> get _cancelled => Failure(AppFailure.cancelled(Operation.media));
  Result<void> get _failed => Failure(
    AppFailure(
      kind: FailureKind.parse,
      operation: Operation.media,
      retryPolicy: RetryPolicy.manual,
    ),
  );
  @override
  Future<Result<void>> play(MediaRef media, AudioFormat format) {
    final generation = ++_generation;
    _cancellation?.cancel();
    return _serial(() async {
      if (_closed || generation != _generation) return _cancelled;
      await _release();
      if (media.sourceId != LocalBookIdentity.sourceId) {
        return Failure(
          AppFailure(kind: FailureKind.unsupported, operation: Operation.media),
        );
      }
      final cancellation = _cancellation = CancellationSource();
      try {
        final result = await books.readMedia(
          media,
          cancellation: cancellation.token,
        );
        if (_closed || generation != _generation) return _cancelled;
        if (result case Failure(:final failure)) return Failure<void>(failure);
        final bytes = (result as Success<Uint8List>).value;
        if (bytes.length > 32 * 1024 * 1024) {
          return Failure(
            AppFailure(kind: FailureKind.tooLarge, operation: Operation.media),
          );
        }
        _directory = await _createDirectory();
        final file = File(
          '${_directory!.path}${Platform.pathSeparator}audio.${format.name}',
        );
        await file.writeAsBytes(bytes, flush: true);
        if (_closed || generation != _generation) {
          await _release();
          return _cancelled;
        }
        final device = _device ??= _createDevice();
        _subscription ??= device.states.listen(
          (state) {
            if (!_closed) _states.add(state);
          },
          onError: (Object _) {
            if (!_closed) _states.add(AudioPlaybackState.stopped);
          },
        );
        await device.open(file.path);
        if (_closed || generation != _generation) {
          await _release();
          return _cancelled;
        }
        await device.resume();
        if (_closed || generation != _generation) {
          await _release();
          return _cancelled;
        }
        return const Success<void>(null);
      } catch (_) {
        await _release();
        return _failed;
      }
    });
  }

  Future<Result<void>> _control(Future<void> Function(AudioDevice) action) =>
      _serial(() async {
        if (_closed || _device == null || _directory == null) return _cancelled;
        try {
          await action(_device!);
          return const Success<void>(null);
        } catch (_) {
          return _failed;
        }
      });
  @override
  Future<Result<void>> resume() => _control((d) => d.resume());
  @override
  Future<Result<void>> pause() => _control((d) => d.pause());
  Future<void> _release() async {
    try {
      await _device?.stop();
    } catch (_) {
      /* Cleanup remains authoritative. */
    }
    final directory = _directory;
    _directory = null;
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {
        /* OS temporary storage. */
      }
    }
  }

  @override
  Future<void> stop() {
    _generation++;
    _cancellation?.cancel();
    return _serial(() async {
      await _release();
      if (!_closed) _states.add(AudioPlaybackState.stopped);
    });
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _generation++;
    _cancellation?.cancel();
    return _closing = _serial(() async {
      await _subscription?.cancel();
      await _release();
      try {
        await _device?.close();
      } catch (_) {
        /* Do not surface raw plugin errors. */
      }
      await _states.close();
    });
  }
}
