import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:shiori/domain/models/release_identity.dart';
import 'package:shiori/features/home/desktop_shell.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/features/updates/update_controller.dart';
import 'package:shiori/features/updates/update_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import '../../support/fake_update_repository.dart';

class ControlledUpdates extends FakeUpdateRepository {
  int loads = 0, downloads = 0;
  Completer<void>? loading, checking, downloading;
  CancellationToken? checkToken, downloadToken;
  void Function(int)? progress;

  Future<void> waitFor(Completer<void>? gate, CancellationToken token) async {
    if (gate != null) await Future.any([gate.future, token.whenCancelled]);
    UpdateController.checkCancelled(token);
  }

  @override
  Future<UpdatePreferences> loadPreferences() async {
    loads++;
    await loading?.future;
    return preferences;
  }

  @override
  Future<UpdateCandidate?> check(
    UpdateChannel channel,
    CancellationToken token,
  ) async {
    checks++;
    checkToken = token;
    await waitFor(checking, token);
    if (failure case final error?) throw error;
    return result;
  }

  @override
  Future<void> download(
    UpdateCandidate candidate,
    CancellationToken token,
    void Function(int) onProgress,
  ) async {
    downloads++;
    downloadToken = token;
    progress = onProgress;
    await waitFor(downloading, token);
    onProgress(candidate.bytes);
    restored = candidate;
  }
}

class UpdatesHarness {
  UpdatesHarness(this.tester, {ControlledUpdates? repository})
    : repo = repository ?? ControlledUpdates();
  final WidgetTester tester;
  final ControlledUpdates repo;
  final env = FixtureEnvironment();
  final navigation = HomeNavigation(HomeSection.updates);
  DateTime now = DateTime.utc(2026, 1, 1);
  Completer<void>? beforeInstall;
  late final controller = UpdateController(
    repo,
    now: () => now,
    beforeInstall: () async => await beforeInstall?.future,
  );
  final opened = <Uri>[];
  bool openResult = true;
  Finder get page => find.byType(UpdateScreen);
  Finder get view => find.descendant(of: page, matching: find.byType(ListView));
  Finder get scrollable =>
      find.descendant(of: view, matching: find.byType(Scrollable)).first;
  ScrollableState get scroll => tester.state(scrollable);
  AppLocalizations get l => AppLocalizations.of(tester.element(page));
  NavigatorState get workspace => tester.state(
    find
        .descendant(
          of: find.byType(DesktopShell),
          matching: find.byType(Navigator),
        )
        .first,
  );
  Widget screen(BuildContext context) => UpdateScreen(
    controller: controller,
    openPage: (uri) async {
      opened.add(uri);
      return openResult;
    },
  );

  Future<void> pump({
    double width = 1280,
    double height = 720,
    double scale = 1,
    String lang = 'en',
    bool shell = true,
    bool settle = true,
    double? bounded,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view
      ..physicalSize = Size(width, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShioriApp(
        locale: Locale(lang),
        overlayBuilder: (context, child) => Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child,
          ),
        ),
        routes: shell ? const AppRoutes() : AppRoutes(home: screen),
        homeBuilder: !shell
            ? null
            : (context, app) {
                final home = ReadingHome(
                  repository: env.novels,
                  library: env.library,
                  sources: [env.source.descriptor],
                  navigation: navigation,
                  updates: screen,
                );
                return bounded == null
                    ? home
                    : Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(width: bounded, child: home),
                      );
              },
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> resize(double width, {bool settle = true}) async {
    tester.view.physicalSize = Size(width, tester.view.physicalSize.height);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> show(Finder target, {double delta = 200}) async {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: scrollable,
      maxScrolls: 30,
    );
    await tester.ensureVisible(target);
    await tester.pump();
    expect(target.hitTestable(), findsOneWidget);
  }

  Future<void> tap(Finder target, {bool settle = true}) async {
    await show(target);
    await tester.tap(target);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> section(String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ShellNavigation),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == label,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await controller.shutdown();
    controller.dispose();
    navigation.dispose();
    await tester.runAsync(env.close);
  }
}
