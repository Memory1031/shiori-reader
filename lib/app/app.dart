import 'package:flutter/material.dart';

import '../shared/widgets/controller_scope.dart';
import 'app_controller.dart';
import 'routes.dart';
import 'theme.dart';

AppController _defaultController() => AppController();

class ShioriApp extends StatelessWidget {
  const ShioriApp({
    super.key,
    this.createController = _defaultController,
    this.routes = const AppRoutes(),
  });

  final AppController Function() createController;
  final AppRoutes routes;

  @override
  Widget build(BuildContext context) => ControllerScope<AppController>(
    create: createController,
    builder: (context, controller) => MaterialApp(
      title: 'Shiori',
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: appThemeMode(controller.settings.themeMode),
      home: Builder(builder: routes.buildHome),
    ),
  );
}
