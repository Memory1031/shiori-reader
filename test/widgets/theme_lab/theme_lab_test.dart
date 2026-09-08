import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shiori/domain/models/app_settings.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/dev/ui/dev_app.dart';
import 'package:shiori/dev/ui/theme_lab/theme_lab.dart';

void main() {
  test('semantic colors meet reading and control contrast targets', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05));
    }

    for (final accent in AppAccent.values) {
      for (final brightness in Brightness.values) {
        final t = shioriTheme(brightness, accent: accent),
            p = t.extension<ShioriPalette>()!;
        for (final background in [p.paper, p.surface]) {
          expect(contrast(p.ink, background), greaterThanOrEqualTo(4.5));
          expect(contrast(p.secondary, background), greaterThanOrEqualTo(4.5));
          expect(contrast(p.accent, background), greaterThanOrEqualTo(3));
        }
        expect(
          contrast(
            t.colorScheme.primaryContainer,
            t.colorScheme.onPrimaryContainer,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(
            t.colorScheme.secondaryContainer,
            t.colorScheme.onSecondaryContainer,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(t.colorScheme.primary, t.colorScheme.onPrimary),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
  testWidgets(
    'three scenes render, stress states remain usable, optional review screenshots',
    (tester) async {
      tester.view.physicalSize = const Size(1320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(createDevApp(scenarioId: 'themeLab'));
      await tester.pumpAndSettle();
      expect(find.byType(LabShelf), findsOneWidget);
      expect(find.byType(LabDetail), findsOneWidget);
      expect(find.byType(LabReader), findsOneWidget);
      Future<void> capture(String variant) async {
        if (!const bool.fromEnvironment('SHIORI_CAPTURE_LAB')) return;
        for (var i = 0; i < 3; i++) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(ValueKey('lab-$i')),
          );
          final image = await tester.runAsync(
            () => boundary.toImage(pixelRatio: 1),
          );
          final bytes = await tester.runAsync(
            () => image!.toByteData(format: ui.ImageByteFormat.png),
          );
          image!.dispose();
          await tester.runAsync(() async {
            await Directory(
              '.tooling/evidence/theme-lab',
            ).create(recursive: true);
            await File(
              '.tooling/evidence/theme-lab/$variant-$i.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
      }

      await capture('light-zh');
      await tester.tap(find.text('中 / EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Night'));
      await tester.pumpAndSettle();
      await capture('dark-en');
      final width = tester.widget<DropdownButton<double>>(
        find.byType(DropdownButton<double>).first,
      );
      width.onChanged!(320);
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButton<double>>(
            find.byType(DropdownButton<double>).last,
          )
          .onChanged!(2);
      await tester.pumpAndSettle();
      for (final state in LabState.values) {
        tester
            .widget<DropdownButton<LabState>>(
              find.byType(DropdownButton<LabState>),
            )
            .onChanged!(state);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: state.name);
      }
      // Wide canvas and intermediate scaling exercise the adaptive shelf grid.
      tester
          .widget<DropdownButton<double>>(
            find.byType(DropdownButton<double>).first,
          )
          .onChanged!(840);
      tester
          .widget<DropdownButton<double>>(
            find.byType(DropdownButton<double>).last,
          )
          .onChanged!(1.3);
      await tester.tap(find.text('中 / EN'));
      await tester.pump();
      for (final state in LabState.values) {
        tester
            .widget<DropdownButton<LabState>>(
              find.byType(DropdownButton<LabState>),
            )
            .onChanged!(state);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: 'wide ${state.name}');
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
