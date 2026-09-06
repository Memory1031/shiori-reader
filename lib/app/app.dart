import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
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
    this.locale,
  });

  final AppController Function() createController;
  final AppRoutes routes;

  /// null follows system preferences. Kept in presentation, not ReaderSettings.
  final Locale? locale;

  @override
  Widget build(BuildContext context) => ControllerScope<AppController>(
    create: createController,
    builder: (context, controller) => MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: appThemeMode(controller.settings.themeMode),
      home: Builder(
        builder: (context) => LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (controller.isLoadingSettings)
                LinearProgressIndicator(
                  semanticsLabel: AppLocalizations.of(context).loadingSettings,
                ),
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
