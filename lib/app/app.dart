import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../shared/widgets/controller_scope.dart';
import '../shared/widgets/state_views.dart';
import 'app_controller.dart';
import 'routes.dart';
import 'theme.dart';
import 'appearance_panel.dart';
import 'launch_view.dart';
import 'window_caption.dart';

AppController _defaultController() => AppController();

class ShioriApp extends StatefulWidget {
  const ShioriApp({
    super.key,
    this.createController = _defaultController,
    this.routes = const AppRoutes(),
    this.locale,
    this.homeBuilder,
    this.overlayBuilder,
    this.navigatorKey,
    this.scaffoldMessengerKey,
    this.captionSender,
  });

  final Widget Function(BuildContext, Widget)? overlayBuilder;

  /// Overrides the native sender for caption integration tests.
  final CaptionSender? captionSender;
  final GlobalKey<NavigatorState>? navigatorKey;
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;
  final AppController Function() createController;
  final AppRoutes routes;
  final Widget Function(BuildContext, AppController)? homeBuilder;

  /// null follows system preferences. Kept in presentation, not ReaderSettings.
  final Locale? locale;

  @override
  State<ShioriApp> createState() => _ShioriAppState();
}

class _ShioriAppState extends State<ShioriApp> {
  late final WindowCaptionController? _caption =
      Platform.isWindows || widget.captionSender != null
      ? WindowCaptionController(sender: widget.captionSender)
      : null;

  @override
  void dispose() {
    _caption?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ControllerScope<AppController>(
    create: widget.createController,
    builder: (context, controller) => MaterialApp(
      navigatorKey: widget.navigatorKey,
      navigatorObservers: [?_caption],
      scaffoldMessengerKey: widget.scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final app = widget.overlayBuilder?.call(context, child!) ?? child!;
        return _caption == null
            ? app
            : WindowCaptionSync(controller: _caption, child: app);
      },
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: widget.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: appTheme(Brightness.light, accent: controller.settings.accent),
      darkTheme: appTheme(Brightness.dark, accent: controller.settings.accent),
      themeMode: appThemeMode(controller.settings.themeMode),
      themeAnimationDuration: Duration.zero,
      home: WindowCaptionScope.appDefault(
        child: Builder(
          builder: (context) => LayoutBuilder(
            builder: (context, constraints) => controller.isLoadingSettings
                ? const LaunchView()
                : Column(
                    children: [
                      if (controller.isLoadingSettings)
                        LinearProgressIndicator(
                          semanticsLabel: AppLocalizations.of(
                            context,
                          ).loadingSettings,
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
                                onRetry: controller.retrySettings,
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child:
                            widget.homeBuilder?.call(context, controller) ??
                            widget.routes.buildHome(
                              context,
                              onAppearance: () =>
                                  showAppAppearance(context, controller),
                            ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}
