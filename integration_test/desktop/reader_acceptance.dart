// Manual Windows acceptance entry. The caller supplies an owned, empty root.
// This entry never launches another process or sends global input.
import 'dart:io';

import 'package:flutter/material.dart';
// Test-only adapters use the already resolved platform implementations.
// ignore: depend_on_referenced_packages
import 'package:path_provider_windows/path_provider_windows.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shiori/app/production_app.dart';
import 'package:shiori/data/local/files/app_paths.dart';

class _PreferencePaths extends PathProviderWindows {
  _PreferencePaths(this.directory);
  final String directory;
  @override
  Future<String> getApplicationSupportPath() async => directory;
}

class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Desktop acceptance is offline');
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || args.length != 1) {
    throw StateError('Expected Windows and one owned acceptance directory');
  }
  final root = Directory(args.single).absolute;
  final marker = File('${root.path}/reader-acceptance.owner');
  if (!await marker.exists() ||
      await marker.readAsString() != 'shiori-reader-acceptance') {
    throw StateError('Acceptance directory must have its ownership marker');
  }
  final preferences = Directory('${root.path}/preferences');
  await preferences.create(recursive: true);
  SharedPreferencesAsyncPlatform.instance = SharedPreferencesAsyncWindows()
    ..pathProvider = _PreferencePaths(preferences.path);
  HttpOverrides.global = _Offline();
  final paths = AppPaths(
    support: Directory('${root.path}/support'),
    temporary: Directory('${root.path}/temporary'),
    environment: StorageEnvironment.development,
  );
  await paths.prepare();
  runApp(ProductionApp(resolvePaths: () async => paths));
}
