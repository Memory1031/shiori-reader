import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/contracts/contracts.dart';
import '../../features/home/reading_home.dart';
import '../fixtures.dart';
import '../../l10n/generated/app_localizations.dart';

class DevHomePage extends StatefulWidget {
  const DevHomePage({
    super.key,
    this.library,
    this.settings,
    this.onAppearance,
  });
  final LibraryRepository? library;
  final SettingsStore? settings;
  final VoidCallback? onAppearance;
  @override
  State<DevHomePage> createState() => _DevHomePageState();
}

class _DevHomePageState extends State<DevHomePage> {
  final _env = FixtureEnvironment();
  @override
  void dispose() {
    unawaited(_env.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReadingHome(
    environmentLabel: AppLocalizations.of(context).offlineEnvironment,
    repository: _env.novels,
    library: widget.library ?? _env.library,
    sources: [_env.source.descriptor],
    images: _env.images,
    settings: widget.settings ?? _env.settings,
    onAppearance: widget.onAppearance,
  );
}
