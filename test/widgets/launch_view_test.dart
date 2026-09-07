import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/launch_view.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

void main() {
  for (final locale in ['zh', 'en']) {
    testWidgets(
      '$locale launch fits small landscape with large text and reduced motion',
      (tester) async {
        tester.view.physicalSize = const Size(480, 320);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: shioriTheme(
              locale == 'zh' ? Brightness.light : Brightness.dark,
            ),
            home: const LaunchView(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Shiori'), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          isNotNull,
        );
        await tester.ensureVisible(find.byType(LinearProgressIndicator));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
