import 'dart:async';

import '../domain/contracts/contracts.dart';
import '../domain/models/models.dart';
import '../shared/controllers/scoped_controller.dart';

/// App lifetime only; feature controllers belong to their own page scopes.
class AppController extends ScopedController {
  AppController({AppSettingsStore? settingsStore})
    : _settingsStore = settingsStore;

  // An omitted adapter means in-memory defaults,
  // not a fake store or a claim that settings have been persisted.
  final AppSettingsStore? _settingsStore;
  AppSettings settings = AppSettings();
  AppFailure? settingsFailure;
  bool isLoadingSettings = false;
  CancellationSource? _request;
  AppSettings? _pending;
  Future<void>? _writing;

  void setAppearance(AppThemeMode mode) {
    if (isClosed || (settings.themeMode == mode && !isLoadingSettings)) return;
    _setSettings(settings.copyWith(themeMode: mode));
  }

  void setAccent(AppAccent accent) {
    if (isClosed || (settings.accent == accent && !isLoadingSettings)) return;
    _setSettings(settings.copyWith(accent: accent));
  }

  void _setSettings(AppSettings value) {
    _request?.cancel();
    isLoadingSettings = false;
    settings = value;
    _pending = settings;
    update();
    unawaited(_save());
  }

  Future<void> retrySettings() => _pending != null ? _save() : loadSettings();

  Future<bool> saveForExit() async {
    await _save();
    return _settingsStore == null || _pending == null;
  }

  Future<void> _save() {
    if (_settingsStore == null) return Future.value();
    return _writing ??= _drain().whenComplete(() => _writing = null);
  }

  Future<void> _drain() async {
    while (_pending != null) {
      final candidate = _pending!;
      _pending = null;
      Result<void> result;
      try {
        result = await _settingsStore!.save(
          candidate,
          cancellation: CancellationSource().token,
        );
      } catch (_) {
        result = Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.settingsWrite,
          ),
        );
      }
      settingsFailure = result is Failure<void> ? result.failure : null;
      if (!isClosed) update();
      if (result is Failure<void>) {
        _pending ??= candidate;
        break;
      }
    }
  }

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
    unawaited(_save());
    super.onClose();
  }
}
