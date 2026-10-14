import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app_controller.dart';
import 'package:shiori/app/bootstrap.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';

class AppStore implements AppSettingsStore {
  AppSettings value = AppSettings();
  Completer<Result<void>>? pending;
  final writes = <AppSettings>[];
  @override
  Future<Result<AppSettings>> load({
    required CancellationToken cancellation,
  }) async => Success(value);
  @override
  Future<Result<void>> save(
    AppSettings settings, {
    required CancellationToken cancellation,
  }) async {
    writes.add(settings);
    final result = await pending?.future ?? const Success<void>(null);
    if (result is Success<void>) value = settings;
    return result;
  }
}

void main() {
  test(
    'layout failure keeps latest full settings for retry without extra writes',
    () async {
      final store = AppStore()..pending = Completer<Result<void>>();
      final controller = AppController(settingsStore: store);
      controller.setShelfGrid(false);
      controller.setShelfGrid(true);
      controller.setShelfGrid(false);
      controller.setAppearance(AppThemeMode.dark);
      controller.setAccent(AppAccent.softPink);
      expect(store.writes, hasLength(1));
      store.pending!.complete(
        Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.settingsWrite,
          ),
        ),
      );
      expect(await controller.saveForExit(), isFalse);
      expect(
        controller.settings,
        AppSettings(
          themeMode: AppThemeMode.dark,
          accent: AppAccent.softPink,
          shelfGrid: false,
        ),
      );
      expect(controller.settingsFailure, isNotNull);
      store.pending = null;
      await controller.retrySettings();
      expect(store.value, controller.settings);
      expect(store.writes, hasLength(2));
      expect(controller.settingsFailure, isNull);
      controller.setShelfGrid(false);
      expect(store.writes, hasLength(2));
      controller.setAppearance(AppThemeMode.light);
      expect(await controller.saveForExit(), isTrue);
      expect(store.value.shelfGrid, isFalse);
      expect(store.value.accent, AppAccent.softPink);
      controller.onDelete();
      controller.dispose();
    },
  );

  test(
    'old layout acknowledgement cannot revert preview; exit waits for latest write',
    () async {
      final first = Completer<Result<void>>(),
          latest = Completer<Result<void>>();
      final store = AppStore()..pending = first;
      final controller = AppController(settingsStore: store);
      controller.setShelfGrid(false);
      controller.setShelfGrid(true);
      controller.setAppearance(AppThemeMode.dark);
      var exited = false;
      final exit = controller.saveForExit().then((value) {
        exited = true;
        return value;
      });
      store.pending = latest;
      first.complete(const Success(null));
      await Future<void>.delayed(Duration.zero);
      expect(exited, isFalse);
      expect(controller.settings.shelfGrid, isTrue);
      expect(store.value.shelfGrid, isFalse);
      expect(store.writes, hasLength(2));
      latest.complete(const Success(null));
      expect(await exit, isTrue);
      expect(store.value, AppSettings(themeMode: AppThemeMode.dark));
      controller.onDelete();
      controller.dispose();
    },
  );

  testWidgets(
    'accent selection keeps an explicit check through hover and theme changes',
    (tester) async {
      final store = AppStore();
      await tester.pumpWidget(
        createApp(settings: store, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('App appearance'));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final mode in ['Light', 'Dark']) {
        await tester.tap(find.widgetWithText(ChoiceChip, mode));
        await tester.pumpAndSettle();
        for (final label in ['Soft teal', 'Blue grey']) {
          final chip = find.widgetWithText(ChoiceChip, label);
          await tester.tap(chip);
          await tester.pumpAndSettle();
          for (final location in [tester.getCenter(chip), Offset.zero]) {
            await mouse.moveTo(location);
            await tester.pumpAndSettle();
            final selected = tester.widget<ChoiceChip>(chip);
            expect(selected.selected, isTrue);
            // RawChip must not paint an animated selection scrim over a swatch.
            expect(selected.showCheckmark, isFalse);
            expect(
              find.descendant(of: chip, matching: find.byIcon(Icons.check)),
              findsOneWidget,
            );
            final other = find.widgetWithText(
              ChoiceChip,
              label == 'Soft teal' ? 'Blue grey' : 'Soft teal',
            );
            expect(
              find.descendant(of: other, matching: find.byIcon(Icons.check)),
              findsNothing,
            );
            // The swatch keeps its size and accent color when selected.
            final swatch = find.descendant(
              of: chip,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is DecoratedBox &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).shape == BoxShape.circle,
              ),
            );
            expect(tester.getSize(swatch), const Size.square(18));
            expect(
              (tester.widget<DecoratedBox>(swatch).decoration as BoxDecoration)
                  .color,
              Theme.of(tester.element(chip)).colorScheme.primary,
            );
          }
        }
      }
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'appearance control persists independently and survives rebuilding the app',
    (tester) async {
      final store = AppStore();
      await tester.pumpWidget(
        createApp(settings: store, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('App appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Blue grey'));
      await tester.pumpAndSettle();
      expect(store.value.accent, AppAccent.blueGrey);
      expect(store.value.themeMode, AppThemeMode.dark);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(createApp(settings: store));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(store.value.accent, AppAccent.blueGrey);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'slow appearance writes coalesce, failure preserves preview and retry saves latest',
    () async {
      final store = AppStore()..pending = Completer<Result<void>>();
      final controller = AppController(settingsStore: store);
      controller.setAppearance(AppThemeMode.dark);
      controller.setAppearance(AppThemeMode.light);
      controller.setAppearance(AppThemeMode.system);
      controller.setAccent(AppAccent.warmBrown);
      expect(store.writes, hasLength(1));
      store.pending!.complete(
        Failure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.settingsWrite,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.settings.themeMode, AppThemeMode.system);
      expect(controller.settingsFailure, isNotNull);
      store.pending = null;
      await controller.retrySettings();
      expect(store.writes, hasLength(2));
      expect(store.value.themeMode, AppThemeMode.system);
      expect(store.value.accent, AppAccent.warmBrown);
      expect(controller.settingsFailure, isNull);
      controller.onDelete();
      controller.dispose();
    },
  );
}
