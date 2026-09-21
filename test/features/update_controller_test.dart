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
    repository.failure = const UpdateIssue(UpdateProblem.verification);
    await controller.install();
    expect(controller.issue?.problem, UpdateProblem.verification);
    expect(controller.phase, UpdatePhase.downloaded);
    expect(controller.busy, isFalse);
  });
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
}
