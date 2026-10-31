import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:shiori/domain/models/release_identity.dart';
import 'package:shiori/features/updates/update_controller.dart';
import '../support/fake_update_repository.dart';

void main() {
  late FakeUpdateRepository repository;
  late UpdateController controller;
  var now = DateTime.utc(2030);
  setUp(() {
    now = DateTime.utc(2030);
    repository = FakeUpdateRepository();
    controller = UpdateController(repository, now: () => now);
  });
  tearDown(() async {
    await controller.shutdown();
    controller.dispose();
  });
  test(
    'download restore failure does not skip installation recovery',
    () async {
      repository.supportsInstallation = true;
      repository.restoreFailure = const UpdateIssue(UpdateProblem.verification);
      repository.installState = UpdateInstallState.failed;
      await controller.initialize();
      expect(controller.initialized, isTrue);
      expect(controller.installState, UpdateInstallState.failed);
      expect(controller.issue?.problem, UpdateProblem.verification);
      expect(controller.phase, UpdatePhase.idle);
      repository.restoreFailure = null;
      await controller.check();
      expect(repository.checks, 1);
    },
  );
  test(
    'permission return does not auto-install; cancellation can retry without downloading',
    () async {
      repository.supportsInstallation = true;
      repository.restored = fakeUpdateCandidate();
      repository.installState = UpdateInstallState.permissionRequired;
      await controller.initialize();
      await controller.openInstallSettings();
      expect(repository.settingsOpened, 1);
      repository.installState = UpdateInstallState.idle;
      await controller.refreshInstallation();
      expect(repository.installs, 0);
      repository.installState = UpdateInstallState.installing;
      await controller.install();
      expect(controller.busy, isTrue);
      await controller.install();
      await controller.check();
      expect(repository.installs, 1);
      expect(repository.checks, 0);
      repository.installState = UpdateInstallState.cancelled;
      await controller.refreshInstallation();
      expect(controller.busy, isFalse);
      expect(controller.phase, UpdatePhase.downloaded);
      await controller.install();
      expect(repository.installs, 2);
    },
  );
  test('active app work blocks handoff and leaves the package ready', () async {
    repository.supportsInstallation = true;
    repository.restored = fakeUpdateCandidate();
    final guarded = UpdateController(
      repository,
      beforeInstall: () async {
        throw const UpdateIssue(UpdateProblem.busy);
      },
    );
    await guarded.initialize();
    await guarded.install();
    expect(repository.installs, 0);
    expect(guarded.issue?.problem, UpdateProblem.busy);
    expect(guarded.phase, UpdatePhase.downloaded);
    await guarded.shutdown();
    guarded.dispose();
  });
  test('install failure keeps verified download retryable', () async {
    repository.supportsInstallation = true;
    repository.restored = fakeUpdateCandidate();
    await controller.initialize();
    repository.failure = const UpdateIssue(UpdateProblem.installation);
    await controller.install();
    expect(controller.issue?.problem, UpdateProblem.installation);
    expect(controller.phase, UpdatePhase.downloaded);
    expect(controller.busy, isFalse);
  });
  test('untrusted installation candidate requires a fresh check', () async {
    repository.supportsInstallation = true;
    repository.restored = fakeUpdateCandidate();
    await controller.initialize();
    repository.failure = const UpdateIssue(UpdateProblem.verification);
    await controller.install();
    expect(controller.issue?.problem, UpdateProblem.verification);
    expect(controller.phase, UpdatePhase.idle);
    expect(controller.candidate, isNull);
    await controller.install();
    await controller.download();
    expect(repository.installs, 1);
    expect(repository.downloadStarted.isCompleted, isFalse);
  });
  test(
    'channel change invalidates results and throttle but retains server limits',
    () async {
      await controller.initialize();
      await controller.check();
      await controller.setChannel(UpdateChannel.beta);
      expect(controller.preferences.lastChecked, isNull);
      expect(controller.preferences.lastAttempt, isNull);
      await controller.check(manual: false);
      expect(repository.checks, 2);
      await controller.setChannel(UpdateChannel.beta);
      expect(controller.preferences.lastChecked, now);
      repository.failure = UpdateIssue(
        UpdateProblem.rateLimited,
        retryAt: now.add(const Duration(minutes: 5)),
      );
      await controller.check();
      await controller.setChannel(UpdateChannel.stable);
      expect(
        controller.preferences.retryAt,
        now.add(const Duration(minutes: 5)),
      );
      await controller.check();
      await controller.check(manual: false);
      expect(repository.checks, 3);
      expect(repository.preferences.lastChecked, isNull);
    },
  );
  test(
    'invalid restored package still allows a fresh check and download',
    () async {
      repository.restoreFailure = const UpdateIssue(UpdateProblem.verification);
      repository.result = fakeUpdateCandidate();
      await controller.initialize();
      expect(controller.initialized, isTrue);
      expect(controller.issue?.problem, UpdateProblem.verification);
      await controller.check();
      await controller.download();
      expect(controller.phase, UpdatePhase.downloaded);
      expect(controller.issue, isNull);
    },
  );
  test(
    'automatic checks respect preference and persist 24 hour throttle across restart',
    () async {
      await controller.initialize();
      await controller.check(manual: false);
      await controller.check(manual: false);
      expect(repository.checks, 1);
      final reopened = UpdateController(repository, now: () => now);
      await reopened.initialize();
      await reopened.check(manual: false);
      expect(repository.checks, 1);
      reopened.dispose();
      now = now.add(const Duration(hours: 24));
      await controller.check(manual: false);
      expect(repository.checks, 2);
      await controller.setAutomatic(false);
      now = now.add(const Duration(days: 2));
      await controller.check(manual: false);
      expect(repository.checks, 2);
      await controller.check();
      expect(repository.checks, 3);
    },
  );
  test(
    'rate limit blocks both manual and automatic requests until deadline',
    () async {
      repository.failure = UpdateIssue(
        UpdateProblem.rateLimited,
        retryAt: now.add(const Duration(minutes: 5)),
      );
      await controller.initialize();
      await controller.check();
      await controller.check();
      expect(repository.checks, 1);
      expect(
        repository.preferences.retryAt,
        now.add(const Duration(minutes: 5)),
      );
      now = now.add(const Duration(minutes: 6));
      repository.failure = null;
      await controller.check();
      expect(repository.checks, 2);
      expect(controller.issue, isNull);
    },
  );
  test('cancel and shutdown wait until download has stopped', () async {
    repository.result = fakeUpdateCandidate();
    repository.blockDownload = true;
    await controller.initialize();
    await controller.check();
    final download = controller.download();
    await repository.downloadStarted.future;
    expect(controller.phase, UpdatePhase.downloading);
    await controller.shutdown();
    await download;
    expect(controller.busy, isFalse);
    expect(repository.closed, isTrue);
    expect(controller.phase, UpdatePhase.available);
    expect(controller.issue, isNull);
  });
  test(
    'channel switch invalidates old candidates; startup restores verified downloads',
    () async {
      repository.restored = fakeUpdateCandidate();
      await controller.initialize();
      expect(controller.phase, UpdatePhase.downloaded);
      await controller.setChannel(UpdateChannel.beta);
      expect(controller.preferences.channel, UpdateChannel.beta);
      expect(controller.phase, UpdatePhase.downloaded);
      repository.restored = null;
      await controller.setChannel(UpdateChannel.stable);
      expect(controller.candidate, isNull);
      expect(controller.phase, UpdatePhase.idle);
    },
  );
  test('network failure preserves a previously verified download', () async {
    repository.restored = fakeUpdateCandidate();
    repository.failure = const UpdateIssue(UpdateProblem.network);
    await controller.initialize();
    await controller.check();
    expect(controller.phase, UpdatePhase.downloaded);
    expect(controller.issue?.problem, UpdateProblem.network);
  });

  test(
    'direct iOS keeps automatic check timing and never starts downloads',
    () async {
      repository.installed = InstalledUpdateApp(
        version: repository.installed.version,
        build: repository.installed.build,
        availability: UpdateAvailability.enabled,
        release: repository.installed.release,
        installation: const AppInstallation(
          kind: AppInstallationKind.iosApp,
          distribution: DistributionChannel.direct,
        ),
      );
      repository.result = fakeUpdateCandidate();
      await controller.initialize();
      await controller.check(manual: false);
      expect(repository.checks, 1);
      expect(controller.phase, UpdatePhase.available);
      expect(controller.capabilities.method, UpdateMethod.checkOnly);
      await controller.check(manual: false);
      expect(repository.checks, 1);
      await controller.download();
      expect(repository.downloads, 0);
      expect(controller.phase, UpdatePhase.available);
      await controller.check();
      expect(repository.checks, 2);
    },
  );

  test(
    '100 percent waits for verification; verification remains exclusive',
    () async {
      repository.result = fakeUpdateCandidate();
      repository.supportsInstallation = true;
      repository.beforeVerifying = Completer<void>();
      repository.verification = Completer<void>();
      await controller.initialize();
      await controller.check();
      final downloading = controller.download();
      await repository.downloadStarted.future;
      expect(controller.received, controller.candidate!.bytes);
      expect(controller.phase, UpdatePhase.downloading);
      repository.beforeVerifying!.complete();
      await repository.verificationStarted.future;
      expect(controller.phase, UpdatePhase.verifying);
      expect(controller.busy, isTrue);
      final checks = repository.checks;
      await controller.check();
      await controller.download();
      await controller.install();
      expect(repository.checks, checks);
      expect(repository.downloads, 1);
      expect(repository.installs, 0);
      repository.progress!(1);
      expect(controller.received, controller.candidate!.bytes);
      repository.verification!.complete();
      await downloading;
      expect(controller.phase, UpdatePhase.downloaded);
      expect(controller.busy, isFalse);
      repository.verifying!();
      repository.progress!(2);
      expect(controller.phase, UpdatePhase.downloaded);
      expect(controller.received, controller.candidate!.bytes);
    },
  );

  for (final verifying in [false, true]) {
    test(
      'cancel during ${verifying ? 'verification' : 'download'} rejects late callbacks across retry',
      () async {
        repository.result = fakeUpdateCandidate();
        repository.beforeVerifying = verifying ? null : Completer<void>();
        repository.verification = Completer<void>();
        await controller.initialize();
        await controller.check();
        final downloading = controller.download();
        await repository.downloadStarted.future;
        if (verifying) await repository.verificationStarted.future;
        final lateProgress = repository.progress!;
        final lateVerifying = repository.verifying!;
        controller.cancel();
        lateProgress(1);
        lateVerifying();
        expect(
          controller.phase,
          verifying ? UpdatePhase.verifying : UpdatePhase.downloading,
        );
        await downloading;
        expect(controller.phase, UpdatePhase.available);
        expect(controller.issue, isNull);
        expect(repository.restored, isNull);
        repository.beforeVerifying = Completer<void>();
        final retry = controller.download();
        lateProgress(1);
        lateVerifying();
        expect(controller.phase, UpdatePhase.downloading);
        expect(controller.received, controller.candidate!.bytes);
        controller.cancel();
        await retry;
      },
    );
  }

  for (final problem in [UpdateProblem.verification, UpdateProblem.storage]) {
    test('$problem exits verification and allows a new download', () async {
      repository.result = fakeUpdateCandidate();
      repository.verification = Completer<void>();
      await controller.initialize();
      await controller.check();
      final downloading = controller.download();
      await repository.verificationStarted.future;
      repository.failure = UpdateIssue(problem);
      repository.verification!.complete();
      await downloading;
      expect(controller.phase, UpdatePhase.available);
      expect(controller.busy, isFalse);
      expect(controller.issue?.problem, problem);
      repository.failure = null;
      repository.verification = null;
      await controller.download();
      expect(controller.phase, UpdatePhase.downloaded);
      expect(controller.issue, isNull);
    });
  }

  test('shutdown cancels verification before closing the repository', () async {
    repository.result = fakeUpdateCandidate();
    repository.verification = Completer<void>();
    await controller.initialize();
    await controller.check();
    final downloading = controller.download();
    await repository.verificationStarted.future;
    await controller.shutdown();
    await downloading;
    repository.verifying!();
    expect(repository.closed, isTrue);
    expect(repository.restored, isNull);
    expect(controller.phase, UpdatePhase.available);
    expect(controller.busy, isFalse);
  });
}
