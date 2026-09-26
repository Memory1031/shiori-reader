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
            expect(
              find.descendant(of: chip, matching: find.byIcon(Icons.circle)),
              findsNothing,
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
