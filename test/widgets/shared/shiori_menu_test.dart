import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/shared/widgets/shiori_menu.dart';

void main() {
  late Future<String?> selected;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: shioriTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => selected = showMenu<String>(
                context: context,
                position: const RelativeRect.fromLTRB(100, 100, 100, 100),
                items: const [
                  ShioriMenuItem(
                    value: 'open',
                    icon: Icons.menu_book_outlined,
                    label: 'Open',
                  ),
                  ShioriMenuItem(
                    value: 'details',
                    label: 'Details',
                    enabled: false,
                  ),
                  PopupMenuDivider(),
                  ShioriMenuItem(value: 'remove', label: 'Remove'),
                ],
              ),
              child: const Text('More'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
  }

  Finder ink(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell));

  testWidgets(
    'entries tint inset and rounded, and are compact on desktop',
    (tester) async {
      await open(tester);
      final theme = Theme.of(tester.element(find.text('Open')));

      final surfaces = find
          .ancestor(of: ink('Open'), matching: find.byType(Material))
          .evaluate()
          .map((e) => e.widget as Material)
          .toList();
      // The entry's ink lands on a clipped, rounded surface of its own.
      final surface = surfaces.first;
      expect(surface.type, MaterialType.transparency);
      expect(surface.clipBehavior, Clip.antiAlias);
      expect(
        surface.borderRadius,
        BorderRadius.circular(ShioriShape.control - ShioriMenuItem.inset),
      );
      final surfaceRect = tester.getRect(
        find.ancestor(of: ink('Open'), matching: find.byType(Material)).first,
      );
      expect(tester.getRect(ink('Open')), surfaceRect);

      // Inset from the menu's edges, which the menu itself paints.
      final menuRect = tester.getRect(
        find.ancestor(of: ink('Open'), matching: find.byType(Material)).at(1),
      );
      expect(surfaces[1].type, isNot(MaterialType.transparency));
      expect(surfaceRect.left, menuRect.left + ShioriMenuItem.inset);
      expect(surfaceRect.right, menuRect.right - ShioriMenuItem.inset);

      for (final label in ['Open', 'Details', 'Remove']) {
        expect(tester.getSize(ink(label)).height, ShioriMenuItem.compactHeight);
      }
      expect(
        tester.widget<Icon>(find.byIcon(Icons.menu_book_outlined)).color,
        theme.colorScheme.onSurfaceVariant,
      );

      // Hover paints the theme's accent tint on the clipped surface.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(ink('Remove')));
      await tester.pumpAndSettle();
      expect(
        Material.of(tester.element(find.text('Remove'))),
        paints..rect(color: theme.hoverColor),
      );
      await mouse.removePointer();

      // A disabled entry stays; an enabled one returns its value.
      await tester.tap(find.text('Details'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(await selected, 'remove');
      expect(find.text('Open'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'touch platforms keep the touch target height',
    (tester) async {
      await open(tester);
      expect(tester.getSize(ink('Open')).height, kMinInteractiveDimension);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(await selected, 'open');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
