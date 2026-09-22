import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:flutter/services.dart';
import 'package:shiori/features/updates/update_controller.dart';
import 'package:shiori/features/updates/update_screen.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import '../support/fake_update_repository.dart';

void main() {
  testWidgets('project actions remain available without in-app updates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeUpdateRepository()
      ..installed = const InstalledUpdateApp(
        version: '1.2.1',
        build: 10,
        availability: UpdateAvailability.unsupported,
      );
    final controller = UpdateController(repo);
    await controller.initialize();
    addTearDown(() async {
      await controller.shutdown();
      controller.dispose();
    });
    Uri? opened;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: UpdateScreen(
          controller: controller,
          openPage: (page) async {
            opened = page;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(UpdateScreen)));
    expect(find.text('v1.2.1'), findsOneWidget);
    expect(find.text(l.updateUnsupported), findsOneWidget);
    expect(find.byKey(const ValueKey('update-check')), findsNothing);
    await tester.tap(find.text('GitHub'));
    expect(opened.toString(), 'https://github.com/Memory1031/shiori-reader');
    await tester.tap(find.text(l.updateCopyVersion));
    await tester.pumpAndSettle();
    expect(copied, contains('Shiori 1.2.1\nBuild: 10\nPlatform:'));
    expect(find.text(l.updateVersionCopied), findsOneWidget);
    await tester.tap(find.text(l.updateLicenses));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language channel switch displays not checked until requested',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FakeUpdateRepository();
        final controller = UpdateController(repo);
        await controller.initialize();
        await controller.check();
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: UpdateScreen(
              controller: controller,
              openPage: (_) async => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(UpdateScreen)),
        );
        expect(find.text(l.updateNeverChecked), findsNothing);
        await tester.tap(find.byKey(const ValueKey('update-channel')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.updateBeta).last);
        await tester.pumpAndSettle();
        expect(find.text(l.updateNeverChecked), findsOneWidget);
        expect(repo.checks, 1);
        expect(controller.preferences.lastChecked, isNull);
        await tester.pumpWidget(const SizedBox());
        await controller.shutdown();
        controller.dispose();
      },
    );
    testWidgets('$language installation permission, cancellation and retry', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeUpdateRepository()
        ..supportsInstallation = true
        ..restored = fakeUpdateCandidate()
        ..installState = UpdateInstallState.permissionRequired;
      final controller = UpdateController(repo);
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: UpdateScreen(
            controller: controller,
            openPage: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(tester.element(find.byType(UpdateScreen)));
      final scroll = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text(l.updateInstallSettings),
        300,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l.updateInstallSettings));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.updateInstallSettings));
      await tester.pumpAndSettle();
      expect(repo.settingsOpened, 1);
      expect(repo.installs, 0);
      repo.installState = UpdateInstallState.cancelled;
      await controller.refreshInstallation();
      await tester.pumpAndSettle();
      expect(find.text(l.updateInstallCancelled), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('update-install')),
        200,
        scrollable: scroll,
      );
      final installButton = find.byKey(const ValueKey('update-install'));
      expect(
        tester.getTopLeft(installButton).dy -
            tester.getBottomLeft(find.text(l.updateInstallCancelled)).dy,
        greaterThanOrEqualTo(12),
      );
      repo.installState = UpdateInstallState.failed;
      await controller.refreshInstallation();
      await tester.pumpAndSettle();
      expect(find.text(l.updateInstallFailed), findsOneWidget);
      expect(
        tester.getTopLeft(installButton).dy -
            tester.getBottomLeft(find.text(l.updateInstallFailed)).dy,
        greaterThanOrEqualTo(12),
      );
      await tester.ensureVisible(installButton);
      await tester.pumpAndSettle();
      repo.installState = UpdateInstallState.installing;
      await tester.tap(find.byKey(const ValueKey('update-install')));
      await tester.pump();
      expect(repo.installs, 1);
      expect(installButton, findsNothing);
      expect(find.text(l.updateInstalling), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(l.updateCancel), findsNothing);
      repo.installState = UpdateInstallState.cancelled;
      await controller.refreshInstallation();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(installButton).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await controller.shutdown();
      controller.dispose();
    });
    for (final width in [390.0, 1280.0]) {
      testWidgets('$language updates at width $width and large text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FakeUpdateRepository()
          ..result = fakeUpdateCandidate(
            notes:
                '## Changes\n\n- **EPUB** fix\n* Windows fix\n'
                '- Release notes <b>plain text</b>\n- More details',
          );
        final controller = UpdateController(repo);
        await controller.initialize();
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: UpdateScreen(
              controller: controller,
              openPage: (_) async => true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('update-check')));
        await tester.pumpAndSettle();
        expect(repo.checks, 1);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('update-download')),
          300,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('EPUB fix', findRichText: true), findsOneWidget);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('update-download')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('update-download')));
        await tester.pumpAndSettle();
        expect(controller.phase, UpdatePhase.downloaded);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await controller.shutdown();
        controller.dispose();
      });
    }
  }
}
