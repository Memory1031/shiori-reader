import 'dart:async';
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
