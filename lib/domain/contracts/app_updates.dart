import '../models/release_identity.dart';
import '../models/app_distribution.dart';
import '../models/value_model.dart';
import 'cancellation.dart';

export '../models/app_distribution.dart';
export '../models/update_capabilities.dart';

enum UpdateAvailability { enabled, development, unsupported, invalidIdentity }

enum UpdateProblem {
  packageInvalid,
  network,
  rateLimited,
  incomplete,
  verification,
  storage,
  cancelled,
  installation,
  busy,
  instances,
  location,
  workspaceConflict,
}

enum UpdateInstallState {
  idle,
  permissionRequired,
  installing,
  cancelled,
  failed,
  installed,
}

final class UpdateIssue implements Exception {
  const UpdateIssue(this.problem, {this.retryAt});
  final UpdateProblem problem;
  final DateTime? retryAt;
}

final class InstalledUpdateApp extends ValueModel {
  const InstalledUpdateApp({
    required this.version,
    required this.build,
    required this.availability,
    this.release,
    this.installation = const AppInstallation(),
  });
  final String version;
  final int build;
  final UpdateAvailability availability;
  final ReleaseIdentity? release;
  final AppInstallation installation;

  @override
  List<Object?> get values => [
    version,
    build,
    availability,
    release,
    installation,
  ];
}

final class UpdateCandidate extends ValueModel {
  const UpdateCandidate({
    required this.release,
    required this.bytes,
    required this.notes,
    required this.page,
  });
  final ReleaseIdentity release;
  final int bytes;
  final String notes;
  final Uri page;
  @override
  List<Object?> get values => [release, bytes, notes, page];
}

final class UpdatePreferences extends ValueModel {
  const UpdatePreferences({
    required this.channel,
    this.automatic = true,
    this.lastAttempt,
    this.lastChecked,
    this.retryAt,
  });
  final UpdateChannel channel;
  final bool automatic;
  final DateTime? lastAttempt;
  final DateTime? lastChecked;
  final DateTime? retryAt;
  @override
  List<Object?> get values => [
    channel,
    automatic,
    lastAttempt,
    lastChecked,
    retryAt,
  ];
}

/// App-owned service. Pages borrow it; cancellation ends I/O before completing.
/// Candidates and recovered downloads have already passed manifest verification.
abstract interface class AppUpdateRepository {
  InstalledUpdateApp get installed;
  bool get supportsInstallation;
  Future<UpdateInstallState> installationStatus();
  Future<void> openInstallSettings();
  Future<UpdateInstallState> install(
    UpdateCandidate candidate,
    CancellationToken token,
  );
  Future<UpdatePreferences> loadPreferences();
  Future<void> savePreferences(UpdatePreferences preferences);
  Future<UpdateCandidate?> restore(
    UpdateChannel channel,
    CancellationToken token,
  );
  Future<UpdateCandidate?> check(
    UpdateChannel channel,
    CancellationToken token,
  );

  /// [onVerifying] runs after the download stream and file writes close,
  /// before package integrity verification begins.
  Future<void> download(
    UpdateCandidate candidate,
    CancellationToken token,
    void Function(int received) onProgress, {
    void Function()? onVerifying,
  });
  Future<void> close();
}
