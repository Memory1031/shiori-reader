import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:shiori/domain/models/release_identity.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/updates/update_controller.dart';
import 'package:shiori/features/updates/update_screen.dart';
import 'package:shiori/shared/widgets/desktop_content_frame.dart';
import '../../support/fake_update_repository.dart';
import 'harness.dart';

final windows = TargetPlatformVariant.only(TargetPlatform.windows);
final check = find.byKey(const ValueKey('update-check'));
final channel = find.byKey(const ValueKey('update-channel'));
final download = find.byKey(const ValueKey('update-download'));
final install = find.byKey(const ValueKey('update-install'));

void main() {
  for (final width in [900.0, 1280.0, 1600.0, 1920.0]) {
    testWidgets('Updates chrome and content at $width', (tester) async {
      final h = UpdatesHarness(tester);
      await h.controller.initialize();
      await h.pump(width: width);
      final viewport = tester.getRect(h.view);
      final chrome = tester.getRect(find.byType(DesktopPageToolbar));
      final settings = tester.getRect(channel);
      final gutter = width < 1200 ? 24.0 : 32.0;
      expect(viewport.left, width < 1200 ? 72 : 232);
      expect(viewport.right, width);
      expect(chrome.left, viewport.left + gutter);
      expect(chrome.right, viewport.right - gutter);
      expect(settings.width, 640);
      expect(settings.center.dx, viewport.center.dx);
      expect(find.byType(BackButton), findsNothing);
      expect(check, findsOneWidget);
      expect(
        find.descendant(of: find.byType(DesktopPageToolbar), matching: check),
        findsNothing,
      );
      expect(
        tester.getRect(
          find.descendant(of: h.view, matching: find.byType(Scrollbar)),
        ),
        viewport,
      );
      expect(h.repo.checks, 0);
      expect(tester.takeException(), isNull);
      await h.close();
    }, variant: windows);
  }

  testWidgets(
    'bounded Shell uses scoped gutter; standalone pushed route keeps Back',
    (tester) async {
      final h = UpdatesHarness(tester);
      await h.controller.initialize();
      await h.pump(width: 1920, bounded: 900);
      expect(tester.getRect(h.view).width, 828);
      final chrome = tester.getRect(find.byType(DesktopPageToolbar));
      expect(chrome.left, 96);
      expect(chrome.right, 876);
      expect(
        tester.getRect(channel).center.dx,
        tester.getRect(h.view).center.dx,
      );
      final root = Navigator.of(tester.element(h.page), rootNavigator: true);
      unawaited(root.push(MaterialPageRoute<void>(builder: h.screen)));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      expect(tester.getRect(find.byType(DesktopPageToolbar)).left, 32);
      expect(tester.getRect(h.view).width, 1920);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(DesktopPageToolbar)), chrome);
      await h.close();
    },
    variant: windows,
  );

  testWidgets('Workspace margin wheel, thumb drag and breakpoint identity', (
    tester,
  ) async {
    final h = UpdatesHarness(tester);
    h.repo.restored = fakeUpdateCandidate(
      notes: List.filled(25, '- Detailed release note').join('\n'),
    );
    await h.controller.initialize();
    await h.pump(width: 1920, height: 500);
    final scroll = h.scroll,
        viewport = tester.element(h.view),
        page = tester.element(h.page);
    final owner = tester.widget<ListView>(h.view).controller;
    final workspace = h.workspace;
    final candidate = h.controller.candidate;
    final bounds = tester.getRect(h.view);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: Offset(bounds.right - 25, bounds.center.dy),
        scrollDelta: const Offset(0, 240),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    final offset = scroll.position.pixels;
    for (final width in [839.0, 840.0, 839.0, 1199.0, 1200.0, 1199.0, 1920.0]) {
      await h.resize(width);
      expect(tester.element(h.page), same(page));
      expect(tester.element(h.view), same(viewport));
      expect(tester.widget<ListView>(h.view).controller, same(owner));
      expect(h.scroll, same(scroll));
      expect(h.workspace, same(workspace));
      expect(
        tester.widget<UpdateScreen>(h.page).controller,
        same(h.controller),
      );
      expect(h.controller.candidate, same(candidate));
      expect(h.controller.phase, UpdatePhase.downloaded);
      expect(scroll.position.pixels, closeTo(offset, 1));
      expect(
        find.byType(DesktopPageChrome),
        width >= 840 ? findsOneWidget : findsNothing,
      );
    }
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final thumb = Offset(bounds.right - 4, bounds.top + 16);
    await mouse.addPointer(location: thumb);
    await mouse.moveTo(thumb + const Offset(0, 1));
    await tester.pumpAndSettle();
    await mouse.down(thumb);
    await mouse.moveBy(const Offset(0, 100));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(150));
    await mouse.removePointer();
    final l = h.l;
    await h.section(l.shelfTitle);
    await h.section(l.updateTitle);
    expect(h.navigation.section, HomeSection.updates);
    expect(h.workspace, same(workspace));
    await h.section(l.searchTitle);
    await h.section(l.updateTitle);
    expect(h.workspace, same(workspace));
    expect(h.controller.candidate, same(candidate));
    expect(h.controller.phase, UpdatePhase.downloaded);
    expect(h.repo.closed, isFalse);
    expect(h.repo.loads, 1);
    expect(h.repo.checks, 0);
    await h.close();
  }, variant: windows);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'wide $platform preserves mobile and route primary',
      (tester) async {
        final h = UpdatesHarness(tester);
        await h.controller.initialize();
        await h.pump(width: 1920, shell: false);
        expect(find.byType(DesktopPageChrome), findsNothing);
        expect(find.byType(AppBar), findsOneWidget);
        expect(tester.getRect(h.view).width, 640);
        expect(tester.getRect(channel).width, 640 - 48);
        expect(tester.widget<ListView>(h.view).controller, isNull);
        final scaffold = find.descendant(
          of: h.page,
          matching: find.byType(Scaffold),
        );
        expect(
          PrimaryScrollController.of(tester.element(scaffold)).positions.single,
          same(h.scroll.position),
        );
        expect(check, findsOneWidget);
        await h.close();
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('short large text $language $brightness remains usable', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final h = UpdatesHarness(tester);
        h.repo.result = fakeUpdateCandidate();
        h.repo.supportsInstallation = true;
        await h.controller.initialize();
        await h.pump(width: 900, height: 420, scale: 2, lang: language);
        final bar = tester.getRect(find.byType(DesktopPageToolbar));
        expect(bar.bottom, lessThan(420));
        h.repo.checking = Completer<void>();
        await h.tap(check, settle: false);
        await h.tap(find.text(h.l.updateCancel));
        expect(h.repo.checkToken!.isCancelled, isTrue);
        h.repo.checking = null;
        await h.show(check, delta: -200);
        await h.tap(check);
        expect(h.repo.checks, 2);
        await h.tap(download);
        expect(h.controller.phase, UpdatePhase.downloaded);
        await h.show(install);
        await h.show(find.text(h.l.updateCopyVersion));
        await h.show(channel, delta: -200);
        final tile = tester.getRect(channel);
        final trailing = tester.getRect(
          find.descendant(
            of: channel,
            matching: find.byIcon(Icons.chevron_right),
          ),
        );
        expect(trailing.right, lessThanOrEqualTo(tile.right));
        expect(tester.takeException(), isNull);
        await h.close();
      }, variant: windows);
    }
  }

  testWidgets(
    'RTL toolbar, channel and project trailing; candidate stays bounded',
    (tester) async {
      final h = UpdatesHarness(tester);
      h.repo.restored = fakeUpdateCandidate();
      await h.controller.initialize();
      await h.pump(width: 1280, direction: TextDirection.rtl);
      final chrome = tester.getRect(find.byType(DesktopPageToolbar));
      expect(chrome.left, 32);
      expect(chrome.right, 1280 - 232 - 32);
      final title = find.descendant(
        of: find.byType(DesktopPageToolbar),
        matching: find.text(h.l.updateTitle),
      );
      expect(tester.getRect(title).right, chrome.right);
      final trailing = tester.getRect(
        find.descendant(
          of: channel,
          matching: find.byIcon(Icons.chevron_right),
        ),
      );
      expect(trailing.center.dx, lessThan(tester.getRect(channel).center.dx));
      await h.show(find.text('GitHub'));
      final github = find.widgetWithText(ListTile, 'GitHub');
      expect(
        tester
            .getRect(
              find.descendant(
                of: github,
                matching: find.byIcon(Icons.north_east),
              ),
            )
            .center
            .dx,
        lessThan(tester.getRect(github).center.dx),
      );
      expect(tester.takeException(), isNull);
      await h.close();
    },
    variant: windows,
  );

  for (final availability in UpdateAvailability.values.where(
    (a) => a != UpdateAvailability.enabled,
  )) {
    testWidgets('$availability keeps branding and project actions', (
      tester,
    ) async {
      final h = UpdatesHarness(tester);
      h.repo.installed = InstalledUpdateApp(
        version: '1.2.1',
        build: 10,
        availability: availability,
      );
      await h.controller.initialize();
      await h.pump();
      expect(find.text('v1.2.1'), findsOneWidget);
      expect(check, findsNothing);
      expect(channel, findsNothing);
      final message = switch (availability) {
        UpdateAvailability.development => h.l.updateDevelopment,
        UpdateAvailability.unsupported => h.l.updateUnsupported,
        _ => h.l.updateInvalidIdentity,
      };
      expect(find.text(message), findsOneWidget);
      await h.show(find.text(h.l.updateCopyVersion));
      await h.close();
    }, variant: windows);
  }

  testWidgets(
    'initialize, checking, cancellation and issue presentation use the existing owner',
    (tester) async {
      final h = UpdatesHarness(tester);
      h.repo.loading = Completer<void>();
      await h.pump(settle: false);
      await h.tap(check, settle: false);
      expect(h.repo.loads, 1);
      expect(h.controller.phase, UpdatePhase.loading);
      expect(find.text(h.l.updateChecking), findsOneWidget);
      expect(tester.widget<TextButton>(check).onPressed, isNull);
      expect(find.text(h.l.updateCancel), findsOneWidget);
      h.repo.loading!.complete();
      await tester.pumpAndSettle();
      expect(h.controller.initialized, isTrue);
      expect(h.repo.checks, 0);
      h.repo.checking = Completer<void>();
      await h.tap(check, settle: false);
      expect(h.controller.phase, UpdatePhase.checking);
      expect(tester.widget<ListTile>(channel).onTap, isNull);
      await h.tap(find.text(h.l.updateCancel));
      expect(h.repo.checkToken!.isCancelled, isTrue);
      expect(h.controller.busy, isFalse);
      h.repo.checking = null;
      await h.tap(check);
      expect(find.text(h.l.updateNoUpdate), findsOneWidget);
      final messages = {
        UpdateProblem.network: h.l.updateNetworkError,
        UpdateProblem.rateLimited: h.l.updateRateLimited('—'),
        UpdateProblem.incomplete: h.l.updateIncomplete,
        UpdateProblem.verification: h.l.updateVerificationError,
        UpdateProblem.storage: h.l.updateStorageError,
        UpdateProblem.packageInvalid: h.l.updatePackageInvalid,
        UpdateProblem.installation: h.l.updateInstallFailedWindows,
        UpdateProblem.busy: h.l.updateInstallBusy,
        UpdateProblem.instances: h.l.updateInstallInstances,
        UpdateProblem.location: h.l.updateInstallLocation,
        UpdateProblem.workspaceConflict: h.l.updateWorkspaceConflict,
      };
      for (final entry in messages.entries) {
        h.repo.failure = UpdateIssue(entry.key);
        await h.tap(check);
        expect(find.text(entry.value), findsOneWidget);
      }
      expect(h.repo.loads, 1);
      await h.close();
    },
    variant: windows,
  );

  testWidgets(
    'download progress and cancel survive resizing without duplicate requests',
    (tester) async {
      final h = UpdatesHarness(tester);
      h.repo.result = fakeUpdateCandidate();
      await h.controller.initialize();
      await h.controller.setChannel(UpdateChannel.beta);
      await h.pump();
      await h.tap(check);
      h.repo.downloading = Completer<void>();
      await h.tap(download, settle: false);
      h.now = h.now.add(const Duration(milliseconds: 200));
      h.repo.progress!(512);
      await tester.pump();
      expect(find.text(h.l.updateProgress(50)), findsOneWidget);
      final viewport = tester.element(h.view),
          owner = tester.widget<ListView>(h.view).controller;
      final target = h.controller.candidate;
      for (final width in [839.0, 840.0, 1199.0, 1200.0]) {
        await h.resize(width, settle: false);
        expect(tester.element(h.view), same(viewport));
        expect(tester.widget<ListView>(h.view).controller, same(owner));
        expect(h.controller.candidate, same(target));
        expect(h.controller.received, 512);
        expect(h.controller.preferences.channel, UpdateChannel.beta);
        expect(h.controller.phase, UpdatePhase.downloading);
      }
      await h.tap(find.text(h.l.updateCancel));
      expect(h.repo.downloadToken!.isCancelled, isTrue);
      expect(h.repo.downloads, 1);
      h.repo.downloading = null;
      await h.tap(download);
      expect(h.controller.phase, UpdatePhase.downloaded);
      expect(install, findsNothing);
      expect(find.text(h.l.updateDownloaded), findsOneWidget);
      expect(h.repo.downloads, 2);
      expect(h.repo.checks, 1);
      expect(h.repo.loads, 1);
      await h.close();
    },
    variant: windows,
  );

  testWidgets(
    'install permission, preparation, restart, cancelled and failed UI remain functional',
    (tester) async {
      final h = UpdatesHarness(tester);
      h.repo
        ..supportsInstallation = true
        ..restored = fakeUpdateCandidate()
        ..installState = UpdateInstallState.permissionRequired;
      await h.controller.initialize();
      await h.pump();
      await h.tap(find.text(h.l.updateInstallSettings));
      expect(h.repo.settingsOpened, 1);
      for (final state in [
        UpdateInstallState.cancelled,
        UpdateInstallState.failed,
      ]) {
        h.repo.installState = state;
        await h.controller.refreshInstallation();
        await tester.pumpAndSettle();
        await h.show(install);
        expect(
          find.text(
            state == UpdateInstallState.cancelled
                ? h.l.updateInstallCancelled
                : h.l.updateInstallFailedWindows,
          ),
          findsOneWidget,
        );
      }
      h.beforeInstall = Completer<void>();
      h.repo.installState = UpdateInstallState.installing;
      await h.tap(install, settle: false);
      expect(h.controller.preparingInstall, isTrue);
      expect(find.text(h.l.updateCancel), findsNothing);
      for (final width in [839.0, 840.0, 1199.0, 1200.0]) {
        await h.resize(width, settle: false);
        expect(h.controller.preparingInstall, isTrue);
        expect(h.repo.installs, 0);
      }
      h.beforeInstall!.complete();
      await tester.pump();
      expect(h.controller.installing, isTrue);
      expect(find.text(h.l.updateRestarting), findsOneWidget);
      expect(find.text(h.l.updateCancel), findsNothing);
      expect(h.repo.installs, 1);
      h.repo.installState = UpdateInstallState.cancelled;
      await h.controller.refreshInstallation();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(install).onPressed, isNotNull);
      await h.close();
    },
    variant: windows,
  );

  testWidgets('channel keyboard selection, Escape, focus and busy guard', (
    tester,
  ) async {
    final h = UpdatesHarness(tester);
    await h.controller.initialize();
    await h.pump();
    final l = h.l;
    final workspace = h.workspace;
    FocusNode focus() => Focus.of(tester.element(find.text(l.updateChannel)));
    for (final value in [UpdateChannel.beta, UpdateChannel.stable]) {
      await h.show(channel);
      focus().requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final selected = find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate((w) => w is ListTile && w.selected),
      );
      expect(selected, findsOneWidget);
      expect(
        find.descendant(
          of: selected,
          matching: find.text(
            h.controller.preferences.channel == UpdateChannel.stable
                ? l.updateStable
                : l.updateBeta,
          ),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<BottomSheet>(),
        isNotNull,
      );
      final option = find.descendant(
        of: sheet,
        matching: find.text(
          value == UpdateChannel.beta ? l.updateBeta : l.updateStable,
        ),
      );
      Focus.of(tester.element(option)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(h.controller.preferences.channel, value);
      expect(h.repo.preferences.channel, value);
      expect(focus().hasFocus, isTrue);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(h.workspace, same(workspace));
    expect(h.navigation.section, HomeSection.updates);
    h.repo.checking = Completer<void>();
    await h.tap(check, settle: false);
    expect(tester.widget<ListTile>(channel).onTap, isNull);
    await h.tap(find.text(l.updateCancel));
    expect(h.repo.checks, 1);
    await h.close();
  }, variant: windows);

  testWidgets(
    'project link fallback, copy version and licenses use existing routes',
    (tester) async {
      final h = UpdatesHarness(tester)..openResult = false;
      await h.controller.initialize();
      await h.pump();
      final l = h.l;
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
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
      await h.tap(find.text('GitHub'));
      expect(
        h.opened.single.toString(),
        'https://github.com/Memory1031/shiori-reader',
      );
      expect(clipboard, h.opened.single.toString());
      expect(find.text(l.updateLinkCopied), findsOneWidget);
      await h.tap(find.text(l.updateCopyVersion));
      expect(
        clipboard,
        'Shiori 1.2.1\nRelease: v1.2.1\nBuild: 10\nPlatform: windows',
      );
      final workspace = h.workspace;
      await h.tap(find.text(l.updateLicenses));
      expect(find.byType(LicensePage), findsOneWidget);
      expect(workspace.canPop(), isTrue);
      workspace.pop();
      await tester.pumpAndSettle();
      expect(h.page, findsOneWidget);
      await h.close();
    },
    variant: windows,
  );
}
