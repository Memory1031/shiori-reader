import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/appearance_panel.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/features/home/reading_home.dart';

void main() {
  for (final locale in ['zh', 'en']) {
    for (final size in [const Size(320, 640), const Size(640, 320)]) {
      testWidgets('home and appearance accessible $locale $size at 2x', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final env = FixtureEnvironment();
          await tester.pumpWidget(
            ShioriApp(
              locale: Locale(locale),
              overlayBuilder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child,
              ),
              homeBuilder: (context, controller) => ReadingHome(
                repository: env.novels,
                library: env.library,
                sources: [env.source.descriptor],
                onAppearance: () => showAppAppearance(context, controller),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(NavigationBar), findsNothing);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await tester.tap(find.byTooltip(locale == 'zh' ? '更多' : 'More'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(locale == 'zh' ? '应用外观' : 'App appearance'),
          );
          await tester.pumpAndSettle();
          for (final label
              in locale == 'zh'
                  ? ['青绿', '蓝灰', '暖棕', '淡粉', '深色', '浅色']
                  : [
                      'Soft teal',
                      'Blue grey',
                      'Warm brown',
                      'Soft pink',
                      'Dark',
                      'Light',
                    ]) {
            final chip = find.widgetWithText(ChoiceChip, label);
            await tester.ensureVisible(chip);
            await tester.pumpAndSettle();
            await tester.tap(chip);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: label);
            expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
            expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
          }
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          // Scrolled-off chips have clipped semantics bounds; their actual
          // target sizes are checked individually while brought into view.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await tester.runAsync(env.close);
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
