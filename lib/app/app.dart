import 'package:flutter/material.dart';

import '../shared/widgets/controller_scope.dart';
import '../shared/widgets/state_views.dart';
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
      home: Builder(
        builder: (context) => LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (controller.isLoadingSettings)
                const LinearProgressIndicator(semanticsLabel: '正在读取设置'),
              if (controller.settingsFailure case final failure?)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .4,
                  ),
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: SafeArea(
                      bottom: false,
                      child: FailureView(
                        failure: failure,
                        onRetry: controller.loadSettings,
                      ),
                    ),
                  ),
                ),
              Expanded(child: routes.buildHome(context)),
            ],
          ),
        ),
      ),
    ),
  );
}
