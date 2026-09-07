import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/app_logger.dart';
import 'files/app_paths.dart';
import 'local_guard.dart';

/// Simple preferences only; never stores bookshelf, progress or sessions.
class PreferencesAppSettingsStore implements AppSettingsStore {
  PreferencesAppSettingsStore({
    required this.preferences,
    required this.paths,
    required this.logger,
  });
  final SharedPreferencesAsync preferences;
  final AppPaths paths;
  final AppLogger logger;
  Future<void> _tail = Future.value();
  @override
  Future<Result<AppSettings>> load({
    required CancellationToken cancellation,
  }) => localRead(Operation.settingsRead, cancellation, () async {
    await _tail;
    checkLocalCancellation(cancellation);
    String? value;
    try {
      value = await preferences.getString(paths.appSettingsKey);
    } on TypeError {
      logger.local(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.settingsRead,
          context: FailureContext.invalidContent,
        ),
      );
      return AppSettings();
    }
    if (value == null) return AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      logger.local(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.settingsRead,
          context: FailureContext.invalidContent,
        ),
      );
      return AppSettings(); // Do not overwrite an unknown future version on read.
    }
  });
  @override
  Future<Result<void>> save(
    AppSettings settings, {
    required CancellationToken cancellation,
  }) {
    final result = _tail.then((_) async {
      try {
        checkLocalCancellation(cancellation);
        await preferences.setString(
          paths.appSettingsKey,
          jsonEncode(settings.toJson()),
        );
        return const Success<void>(null);
      } catch (error) {
        final failure = localFailure(Operation.settingsWrite, error);
        logger.local(failure);
        return Failure<void>(failure);
      }
    });
    _tail = result.then<void>((_) {});
    return result;
  }
}
