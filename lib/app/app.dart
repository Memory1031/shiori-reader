import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/reader/reader_commands.dart';

import '../l10n/generated/app_localizations.dart';
import '../shared/widgets/controller_scope.dart';
import '../shared/widgets/state_views.dart';
import '../shared/widgets/shiori_feedback.dart';
import 'app_controller.dart';
import 'app_exit.dart';
import 'routes.dart';
import 'theme.dart';
import 'appearance_panel.dart';
import 'launch_view.dart';
import 'window_caption.dart';
import '../features/reader/reader_embedded_fonts.dart';

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
    this.shutdown,
  });

  final Widget Function(BuildContext, Widget)? overlayBuilder;

  /// Overrides the native sender for caption integration tests.
  final CaptionSender? captionSender;
  final Future<void> Function()? shutdown;
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
  final _feedback = ShioriFeedbackObserver();
  final _readerFonts = ReaderFontRegistry();
  final _macNavigator = GlobalKey<NavigatorState>();
  AppController? _menuController;
  static const _menu = MethodChannel('dev.shiori.reader/menu');
  static _ShioriAppState? _menuOwner;
  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _menuOwner = this;
      _menu.setMethodCallHandler((call) async {
        if (call.method != 'settings') return;
        final focus = FocusManager.instance.primaryFocus?.context;
        const intent = ReaderCommandIntent(ReaderCommand.settings);
        if (focus != null) {
          final action = Actions.maybeFind<ReaderCommandIntent>(focus);
          if (action != null && action.isEnabled(intent)) {
            Actions.invoke(focus, intent);
            return;
          }
        }
        final context = (widget.navigatorKey ?? _macNavigator).currentContext;
        final controller = _menuController;
        if (mounted && context != null && controller != null) {
          await showAppAppearance(context, controller);
        }
      });
    }
  }

  late final WindowCaptionController? _caption =
      Platform.isWindows || Platform.isMacOS || widget.captionSender != null
      ? WindowCaptionController(sender: widget.captionSender)
      : null;

  @override
  void dispose() {
    if (identical(_menuOwner, this)) {
      _menuOwner = null;
      _menu.setMethodCallHandler(null);
    }
    _readerFonts.dispose();
    _caption?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ControllerScope<AppController>(
    create: widget.createController,
    builder: (context, controller) {
      _menuController = controller;
      return MaterialApp(
        navigatorKey:
            widget.navigatorKey ?? (Platform.isMacOS ? _macNavigator : null),
        navigatorObservers: [_feedback, ?_caption],
        scaffoldMessengerKey: widget.scaffoldMessengerKey,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final feedback = ShioriFeedbackHost(
            observer: _feedback,
            child: child!,
          );
          final app =
              widget.overlayBuilder?.call(context, feedback) ?? feedback;
          final page = _caption == null
              ? app
              : WindowCaptionSync(controller: _caption, child: app);
          return ReaderFontScope(
            registry: _readerFonts,
            child: AppExitScope(
              save: controller.saveForExit,
              shutdown: widget.shutdown,
              child: page,
            ),
          );
        },
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        locale: widget.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: appTheme(Brightness.light, accent: controller.settings.accent),
        darkTheme: appTheme(
          Brightness.dark,
          accent: controller.settings.accent,
        ),
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
                              color: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
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
      );
    },
  );
}
