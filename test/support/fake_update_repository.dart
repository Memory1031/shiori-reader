import 'dart:async';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:shiori/domain/contracts/cancellation.dart';
import 'package:shiori/domain/models/release_identity.dart';

class FakeUpdateRepository implements AppUpdateRepository {
  @override
  bool supportsInstallation = false;
  UpdateInstallState installState = UpdateInstallState.idle;
  int installs = 0;
  int settingsOpened = 0;
  @override
  Future<UpdateInstallState> installationStatus() async => installState;
  @override
  Future<void> openInstallSettings() async {
    settingsOpened++;
  }

  @override
  Future<UpdateInstallState> install(
    UpdateCandidate candidate,
    CancellationToken token,
  ) async {
    installs++;
    if (failure case final error?) throw error;
    return installState;
  }

  @override
  InstalledUpdateApp installed = InstalledUpdateApp(
    version: '1.2.1',
    build: 10,
    availability: UpdateAvailability.enabled,
    release: ReleaseIdentity(
      tag: 'v1.2.1',
      version: '1.2.1',
      build: 10,
      commit: 'a' * 40,
    ),
  );
  UpdatePreferences preferences = const UpdatePreferences(
    channel: UpdateChannel.stable,
  );
  UpdateCandidate? result;
  UpdateCandidate? restored;
  UpdateIssue? failure;
  UpdateIssue? restoreFailure;
  bool blockDownload = false;
  bool closed = false;
  int checks = 0;
  final downloadStarted = Completer<void>();
  @override
  Future<UpdatePreferences> loadPreferences() async => preferences;
  @override
  Future<void> savePreferences(UpdatePreferences value) async {
    preferences = value;
  }

  @override
  Future<UpdateCandidate?> restore(
    UpdateChannel channel,
    CancellationToken token,
  ) async {
    if (restoreFailure case final error?) throw error;
    return restored?.release.canReplace(installed.release!, channel) == true
        ? restored
        : null;
  }

  @override
  Future<UpdateCandidate?> check(
    UpdateChannel channel,
    CancellationToken token,
  ) async {
    checks++;
    if (failure case final error?) throw error;
    return result;
  }

  @override
  Future<void> download(
    UpdateCandidate candidate,
    CancellationToken token,
    void Function(int) onProgress,
  ) async {
    downloadStarted.complete();
    onProgress(20);
    if (blockDownload) {
      await token.whenCancelled;
      throw const UpdateIssue(UpdateProblem.cancelled);
    }
    onProgress(candidate.bytes);
    restored = candidate;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

UpdateCandidate fakeUpdateCandidate({
  String notes = 'Release notes <b>plain text</b>',
}) => UpdateCandidate(
  release: ReleaseIdentity(
    tag: 'v1.2.2',
    version: '1.2.2',
    build: 11,
    commit: 'b' * 40,
  ),
  bytes: 1024,
  notes: notes,
  page: Uri.parse(
    'https://github.com/Memory1031/shiori-reader/releases/tag/v1.2.2',
  ),
);
