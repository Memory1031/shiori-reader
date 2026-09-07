import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/routes.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../fixture_scenarios.dart';
import 'scenario_page.dart';
import 'theme_lab/theme_lab.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../domain/contracts/contracts.dart';
import '../../app/app_controller.dart';
import '../../app/appearance_panel.dart';

FixtureScenario? parseDevScenario(String value) {
  if (value.isEmpty) return null;
  for (final scenario in FixtureScenario.values) {
    if (scenario.name == value) return scenario;
  }
  throw ArgumentError.value(
    value,
    'SHIORI_SCENARIO',
    'Unknown fixture scenario',
  );
}

ShioriApp createDevApp({
  String scenarioId = '',
  Locale? locale,
  SettingsStore? settings,
  LibraryRepository? library,
  AppSettingsStore? appSettings,
}) {
  if (scenarioId == 'themeLab') {
    return ShioriApp(
      locale: locale,
      routes: AppRoutes(home: (_) => const ThemeLab()),
    );
  }
  final initial = parseDevScenario(scenarioId);
  return ShioriApp(
    createController: () => AppController(settingsStore: appSettings),
    locale: locale,
    homeBuilder: (context, controller) => DevMenu(
      initial: initial,
      preferences: settings,
      library: library,
      onAppearance: () => showAppAppearance(context, controller),
    ),
  );
}

String scenarioLabel(BuildContext context, FixtureScenario scenario) =>
    Localizations.localeOf(context).languageCode == 'zh'
    ? scenario.labelZh
    : scenario.labelEn;

class DevMenu extends StatefulWidget {
  const DevMenu({
    super.key,
    this.initial,
    this.preferences,
    this.library,
    this.onAppearance,
  });
  final VoidCallback? onAppearance;
  final FixtureScenario? initial;
  final SettingsStore? preferences;
  final LibraryRepository? library;
  @override
  State<DevMenu> createState() => _DevMenuState();
}

class _DevMenuState extends State<DevMenu> {
  @override
  void initState() {
    super.initState();
    if (widget.initial case final initial?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(initial);
      });
    }
  }

  void _open(FixtureScenario scenario) {
    Widget builder(BuildContext context) => DevScenarioPage(
      scenario: scenario,
      settings: widget.preferences,
      library: widget.library,
    );
    const settings = RouteSettings(name: '/dev/scenario');
    Navigator.of(context).push<void>(
      Theme.of(context).platform == TargetPlatform.iOS
          ? CupertinoPageRoute(builder: builder, settings: settings)
          : MaterialPageRoute(builder: builder, settings: settings),
    );
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Shiori DEV',
    actions: [
      IconButton(
        onPressed: widget.onAppearance,
        tooltip: AppLocalizations.of(context).appAppearance,
        icon: const Icon(Icons.palette_outlined),
      ),
    ],
    body: ListView(
      children: [
        ListTile(
          title: Text(AppLocalizations.of(context).labTitle),
          trailing: const Icon(Icons.palette_outlined),
          onTap: () => Navigator.of(
            context,
          ).push<void>(MaterialPageRoute(builder: (_) => const ThemeLab())),
        ),
        for (final scenario in FixtureScenario.values)
          ListTile(
            key: ValueKey(scenario.name),
            title: Text(scenarioLabel(context, scenario)),
            subtitle: Text(scenario.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(scenario),
          ),
      ],
    ),
  );
}
