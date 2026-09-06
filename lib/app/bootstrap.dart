import 'package:flutter/widgets.dart';

import '../domain/contracts/repositories.dart';
import 'app.dart';
import 'app_controller.dart';
import 'routes.dart';

/// Composition entry: future production adapters are assembled here.
/// Feature factories capture their own repositories; widgets never locate them.
ShioriApp createApp({
  SettingsStore? settings,
  AppRoutes routes = const AppRoutes(),
  Locale? locale,
}) => ShioriApp(
  createController: () => AppController(settingsStore: settings),
  routes: routes,
  locale: locale,
);
