import '../models/models.dart';
import 'result.dart';

enum PrefetchPhase { idle, running, paused, budget, partial, complete }

class PrefetchState {
  const PrefetchState({
    this.phase = PrefetchPhase.idle,
    this.target,
    this.currentEnabled = true,
    this.nextEnabled = true,
    this.failures = 0,
  });
  final PrefetchPhase phase;
  final ChapterKey? target;
  final bool currentEnabled, nextEnabled;
  final int failures;
}

abstract interface class ReadingPrefetch {
  PrefetchState get state;
  Stream<PrefetchState> get changes;
  Future<void> enter(ChapterContent content, Catalog? catalog);
  void position(int blockIndex);
  Future<Result<void>> select(ChapterKey? target);
  Future<Result<void>> configure({required bool current, required bool next});
  void pause();
  void resume();
  void leave();
  void active(bool value);
}
