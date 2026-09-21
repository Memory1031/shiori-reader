import 'dart:convert';
import 'dart:io';

import '../../domain/contracts/app_updates.dart';
import '../../domain/models/release_identity.dart';

/// Dedicated disposable update directory, with durable preferences stored apart.
final class UpdateStorage {
  UpdateStorage({required this.directory, required this.preferencesFile});
  final Directory directory;
  final File preferencesFile;
  File file(String name) => File('${directory.path}/$name');
  Future<void> prepare() async => directory.create(recursive: true);

  static Future<Object?> readJson(
    File file, {
    int limit = 6 * 1024 * 1024,
  }) async {
    if (!await file.exists()) return null;
    if (await file.length() > limit) {
      throw const FormatException('Oversized update record');
    }
    return jsonDecode(await file.readAsString());
  }

  static Future<void> writeJson(File file, Object json) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(json), flush: true);
    await temporary.rename(file.path);
  }

  Future<UpdatePreferences> loadPreferences(UpdateChannel initial) async {
    final json = await readJson(preferencesFile, limit: 8192);
    if (json == null) return UpdatePreferences(channel: initial);
    final value = json as Map<String, dynamic>;
    if (value['schema'] != 1) {
      throw const FormatException('Unknown update settings');
    }
    DateTime? date(String key) => value[key] == null
        ? null
        : DateTime.parse(value[key] as String).toUtc();
    return UpdatePreferences(
      channel: UpdateChannel.values.byName(value['channel'] as String),
      automatic: value['automatic'] as bool,
      lastAttempt: date('lastAttempt'),
      lastChecked: date('lastChecked'),
      retryAt: date('retryAt'),
    );
  }

  Future<void> savePreferences(UpdatePreferences value) =>
      writeJson(preferencesFile, {
        'schema': 1,
        'channel': value.channel.name,
        'automatic': value.automatic,
        'lastAttempt': value.lastAttempt?.toUtc().toIso8601String(),
        'lastChecked': value.lastChecked?.toUtc().toIso8601String(),
        'retryAt': value.retryAt?.toUtc().toIso8601String(),
      });
}
