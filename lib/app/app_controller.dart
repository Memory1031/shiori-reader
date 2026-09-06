import 'dart:async';

import '../domain/contracts/contracts.dart';
import '../domain/models/models.dart';
import '../shared/controllers/scoped_controller.dart';

/// App lifetime only; feature controllers belong to their own page scopes.
class AppController extends ScopedController {
  AppController({SettingsStore? settingsStore})
    : _settingsStore = settingsStore;

  // No production store exists until DB-002. Absence means in-memory defaults,
  // not a fake store or a claim that settings have been persisted.
  final SettingsStore? _settingsStore;
  ReaderSettings settings = ReaderSettings();
  AppFailure? settingsFailure;
  bool isLoadingSettings = false;
  CancellationSource? _request;

  @override
  void onInit() {
    super.onInit();
    unawaited(loadSettings());
  }

  Future<void> loadSettings() async {
    if (isClosed || _settingsStore == null) return;
    _request?.cancel();
    final request = CancellationSource();
    _request = request;
    isLoadingSettings = true;
    settingsFailure = null;
    update();
    try {
      final result = await _settingsStore.load(cancellation: request.token);
      if (isClosed || request.token.isCancelled || _request != request) return;
      switch (result) {
        case Success(:final value):
          settings = value;
        case Failure(:final failure):
          if (!failure.isCancellation) settingsFailure = failure;
      }
    } finally {
      request.cancel();
      if (!isClosed && _request == request) {
        _request = null;
        isLoadingSettings = false;
        update();
      }
    }
  }

  @override
  void onClose() {
    _request?.cancel();
    super.onClose();
  }
}
