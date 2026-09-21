import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/contracts/app_updates.dart';
import '../../domain/contracts/cancellation.dart';
import '../../domain/models/release_identity.dart';

enum UpdatePhase { loading, idle, checking, available, downloading, downloaded }

class UpdateController extends ChangeNotifier {
  UpdateController(
    this.repository, {
    DateTime Function()? now,
    this.beforeInstall,
  }) : _now = now ?? DateTime.now;
  final AppUpdateRepository repository;
  final Future<void> Function()? beforeInstall;
  final DateTime Function() _now;
  InstalledUpdateApp get installed => repository.installed;
  late UpdatePreferences preferences = UpdatePreferences(
    channel: installed.release?.channel ?? UpdateChannel.stable,
  );
  UpdatePhase phase = UpdatePhase.loading;
  UpdateCandidate? candidate;
  UpdateIssue? issue;
  int received = 0;
  bool initialized = false;
  UpdateInstallState installState = UpdateInstallState.idle;
  Timer? _installPoll;
  bool get canInstall => repository.supportsInstallation;
  bool get installing => installState == UpdateInstallState.installing;
  bool preparingInstall = false;
  bool _closed = false;
  CancellationSource? _cancel;
  Future<void>? _pending;
  bool get busy => _pending != null || installing;
  bool get enabled => installed.availability == UpdateAvailability.enabled;

  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> _run(Future<void> Function(CancellationToken) action) {
    if (_closed || busy) return Future.value();
    final source = CancellationSource();
    _cancel = source;
    final done = Completer<void>();
    _pending = done.future;
    issue = null;
    _changed();
    unawaited(() async {
      try {
        await action(source.token);
      } on UpdateIssue catch (error) {
        if (error.problem != UpdateProblem.cancelled) issue = error;
      } catch (_) {
        issue = const UpdateIssue(UpdateProblem.storage);
      } finally {
        if (phase == UpdatePhase.checking ||
            phase == UpdatePhase.downloading ||
            phase == UpdatePhase.loading) {
          phase = candidate == null ? UpdatePhase.idle : UpdatePhase.available;
        }
        _cancel = null;
        _pending = null;
        _changed();
        done.complete();
      }
    }());
    return done.future;
  }

  Future<void> initialize() => _run((token) async {
    preferences = await repository.loadPreferences();
    initialized = true;
    candidate = await repository.restore(preferences.channel, token);
    phase = candidate == null ? UpdatePhase.idle : UpdatePhase.downloaded;
    if (canInstall) _installedState(await repository.installationStatus());
  });

  void _installedState(UpdateInstallState value) {
    installState = value;
    _installPoll?.cancel();
    if (installing && !_closed) {
      _installPoll = Timer(const Duration(seconds: 2), refreshInstallation);
    }
    _changed();
  }

  Future<void> refreshInstallation() async {
    if (_closed || !canInstall || _pending != null) return;
    try {
      _installedState(await repository.installationStatus());
    } on UpdateIssue catch (error) {
      issue = error;
      _installedState(UpdateInstallState.failed);
    }
  }

  Future<void> openInstallSettings() => _run((_) async {
    await repository.openInstallSettings();
  });

  Future<void> install() => _run((token) async {
    final target = candidate;
    if (!enabled ||
        !canInstall ||
        phase != UpdatePhase.downloaded ||
        target == null) {
      return;
    }
    preparingInstall = true;
    _changed();
    try {
      await beforeInstall?.call();
      _installedState(await repository.install(target, token));
    } finally {
      preparingInstall = false;
    }
  });

  UpdatePreferences _preferences({
    UpdateChannel? channel,
    bool? automatic,
    DateTime? attempt,
    DateTime? checked,
    DateTime? retry,
    bool clearRetry = false,
  }) => UpdatePreferences(
    channel: channel ?? preferences.channel,
    automatic: automatic ?? preferences.automatic,
    lastAttempt: attempt ?? preferences.lastAttempt,
    lastChecked: checked ?? preferences.lastChecked,
    retryAt: clearRetry ? null : retry ?? preferences.retryAt,
  );

  Future<void> check({bool manual = true}) async {
    if (!enabled || !initialized || busy || _closed) return;
    final now = _now().toUtc();
    final retry = preferences.retryAt;
    if (retry != null && now.isBefore(retry)) {
      if (manual) {
        issue = UpdateIssue(UpdateProblem.rateLimited, retryAt: retry);
        _changed();
      }
      return;
    }
    final last = preferences.lastAttempt;
    if (!manual &&
        (!preferences.automatic ||
            (last != null &&
                now.difference(last) < const Duration(hours: 24)))) {
      return;
    }
    final wasDownloaded = phase == UpdatePhase.downloaded;
    final previous = candidate;
    await _run((token) async {
      phase = UpdatePhase.checking;
      _changed();
      final attempted = _preferences(attempt: now, clearRetry: true);
      await repository.savePreferences(attempted);
      preferences = attempted;
      try {
        final result = await repository.check(preferences.channel, token);
        checkCancelled(token);
        final saved = _preferences(checked: _now().toUtc());
        await repository.savePreferences(saved);
        preferences = saved;
        candidate = result ?? previous;
        phase = wasDownloaded && (result == null || result == previous)
            ? UpdatePhase.downloaded
            : candidate == null
            ? UpdatePhase.idle
            : UpdatePhase.available;
      } on UpdateIssue catch (error) {
        if (error.problem == UpdateProblem.rateLimited) {
          final saved = _preferences(retry: error.retryAt);
          await repository.savePreferences(saved);
          preferences = saved;
        }
        if (wasDownloaded) phase = UpdatePhase.downloaded;
        rethrow;
      }
    });
  }

  static void checkCancelled(CancellationToken token) {
    if (token.isCancelled) throw const UpdateIssue(UpdateProblem.cancelled);
  }

  Future<void> setChannel(UpdateChannel channel) => _run((token) async {
    final saved = _preferences(channel: channel);
    await repository.savePreferences(saved);
    preferences = saved;
    candidate = null;
    phase = UpdatePhase.idle;
    candidate = await repository.restore(channel, token);
    if (candidate != null) phase = UpdatePhase.downloaded;
  });
  Future<void> setAutomatic(bool value) => _run((_) async {
    final saved = _preferences(automatic: value);
    await repository.savePreferences(saved);
    preferences = saved;
  });
  Future<void> download() => _run((token) async {
    final target = candidate;
    if (target == null || !enabled) return;
    phase = UpdatePhase.downloading;
    received = 0;
    _changed();
    var notifiedAt = _now();
    await repository.download(target, token, (value) {
      received = value;
      final now = _now();
      if (value == target.bytes ||
          now.difference(notifiedAt) >= const Duration(milliseconds: 100)) {
        notifiedAt = now;
        _changed();
      }
    });
    phase = UpdatePhase.downloaded;
  });
  void cancel() => _cancel?.cancel();
  Future<void> shutdown() async {
    _closed = true;
    _installPoll?.cancel();
    cancel();
    await _pending;
    await repository.close();
  }
}
