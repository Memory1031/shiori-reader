import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';

/// Owns load cancellation and a bounded, serial trailing write queue.
class ReaderPreferences extends ChangeNotifier {
  ReaderPreferences(this.store);
  final SettingsStore? store;
  final _load = CancellationSource();
  ReaderSettings value = ReaderSettings();
  AppFailure? failure;
  Timer? _timer;
  ReaderSettings? _pending;
  bool _writing = false;
  bool _disposed = false;
  int _revision = 0;

  Future<void> load() async {
    final revision = _revision;
    final result = await store?.load(cancellation: _load.token);
    if (_disposed || revision != _revision) return;
    if (result case Success<ReaderSettings>(value: final loaded)) {
      value = loaded.copyWith(mode: ReaderMode.paged);
      failure = null;
    }
    if (result case Failure<ReaderSettings>(failure: final error)) {
      failure = error;
    }
    notifyListeners();
  }

  void update(ReaderSettings settings) {
    settings = settings.copyWith(mode: ReaderMode.paged);
    if (_disposed || settings == value) return;
    value = settings;
    _revision++;
    _pending = settings;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (_writing || store == null) return;
    _writing = true;
    try {
      while (_pending != null) {
        final settings = _pending!;
        _pending = null;
        // A save accepted before disposal must still be allowed to commit.
        final result = await store!.save(
          settings,
          cancellation: CancellationSource().token,
        );
        failure = result is Failure<void> ? result.failure : null;
        if (!_disposed) notifyListeners();
      }
    } finally {
      _writing = false;
    }
  }

  void retry() {
    if (_revision == 0) {
      unawaited(load());
      return;
    }
    _pending = value;
    unawaited(flush());
  }

  @override
  void dispose() {
    _disposed = true;
    _load.cancel();
    _timer?.cancel();
    unawaited(flush());
    super.dispose();
  }
}
