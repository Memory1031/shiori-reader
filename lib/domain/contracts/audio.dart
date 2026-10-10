import '../models/models.dart';
import 'result.dart';

enum AudioPlaybackState { stopped, playing, paused, completed }

/// One independently owned player. Only explicit local resources can be opened.
abstract interface class AudioPlayback {
  Stream<AudioPlaybackState> get states;
  Future<Result<void>> play(MediaRef media, AudioFormat format);
  Future<Result<void>> resume();
  Future<Result<void>> pause();
  Future<void> stop();
  Future<void> close();
}

abstract interface class AudioPlaybackFactory {
  AudioPlayback createAudioPlayback();
}
