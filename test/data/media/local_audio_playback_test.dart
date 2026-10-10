import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/media/local_audio_playback.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import '../local/support/synthetic_audio.dart';

class AudioBooks implements LocalBookStore {
  Completer<Result<Uint8List>>? pending;
  CancellationToken? token;
  @override
  Future<Result<Uint8List>> readMedia(
    MediaRef ref, {
    required CancellationToken cancellation,
  }) async {
    token = cancellation;
    return pending?.future ?? Success(syntheticWav());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class TestAudioDevice implements AudioDevice {
  final events = StreamController<AudioPlaybackState>.broadcast();
  String? path;
  int starts = 0, pauses = 0, stops = 0, closes = 0;
  Completer<void>? opening;
  bool fail = false;
  @override
  Stream<AudioPlaybackState> get states => events.stream;
  @override
  Future<void> open(String path) async {
    this.path = path;
    await opening?.future;
    if (fail) throw StateError('decoder');
  }

  @override
  Future<void> resume() async {
    starts++;
    events.add(AudioPlaybackState.playing);
  }

  @override
  Future<void> pause() async {
    pauses++;
    events.add(AudioPlaybackState.paused);
  }

  @override
  Future<void> stop() async {
    stops++;
    events.add(AudioPlaybackState.stopped);
  }

  @override
  Future<void> close() async {
    closes++;
    await events.close();
  }
}

void main() {
  final ref = MediaRef(
    sourceId: LocalBookIdentity.sourceId,
    mediaId: '${'a' * 64}/${'b' * 64}',
  );
  test(
    'local audio retains a private file until stop, pause resumes and close is idempotent',
    () async {
      final books = AudioBooks(), device = TestAudioDevice();
      final player = LocalAudioPlayback(books, createDevice: () => device);
      expect(await player.play(ref, AudioFormat.wav), isA<Success<void>>());
      final file = File(device.path!);
      expect(await file.readAsBytes(), syntheticWav());
      expect(await player.pause(), isA<Success<void>>());
      expect(await player.resume(), isA<Success<void>>());
      expect(device.pauses, 1);
      expect(device.starts, 2);
      await player.stop();
      expect(await file.exists(), isFalse);
      await player.close();
      await player.close();
      expect(device.closes, 1);
    },
  );
  test(
    'stop during a delayed book read cancels without opening a player',
    () async {
      final books = AudioBooks()..pending = Completer(),
          device = TestAudioDevice();
      final player = LocalAudioPlayback(books, createDevice: () => device);
      final opening = player.play(ref, AudioFormat.wav);
      await Future<void>.delayed(Duration.zero);
      final stopping = player.stop();
      expect(books.token!.isCancelled, isTrue);
      books.pending!.complete(Success(syntheticWav()));
      expect((await opening).isCancelled, isTrue);
      await stopping;
      expect(device.starts, 0);
      expect(device.path, isNull);
      await player.close();
    },
  );
  test(
    'close during platform preparation prevents late playback and removes the file',
    () async {
      final device = TestAudioDevice()..opening = Completer<void>();
      final prepared = Completer<void>();
      final player = LocalAudioPlayback(
        AudioBooks(),
        createDevice: () {
          prepared.complete();
          return device;
        },
      );
      final opening = player.play(ref, AudioFormat.wav);
      await prepared.future;
      final closing = player.close();
      device.opening!.complete();
      expect((await opening).isCancelled, isTrue);
      await closing;
      expect(device.starts, 0);
      expect(await File(device.path!).exists(), isFalse);
      expect(device.closes, 1);
    },
  );
  test(
    'decoder failure cleans temporary media and is reported as a failure',
    () async {
      final device = TestAudioDevice()..fail = true;
      final player = LocalAudioPlayback(
        AudioBooks(),
        createDevice: () => device,
      );
      expect(await player.play(ref, AudioFormat.wav), isA<Failure<void>>());
      expect(await File(device.path!).exists(), isFalse);
      await player.close();
    },
  );
}
