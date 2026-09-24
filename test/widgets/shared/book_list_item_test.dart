import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/shared/widgets/book_list_tile.dart';

void main() {
  testWidgets('row states use an inset accent tint, not grey ink', (
    tester,
  ) async {
    final theme = shioriTheme(Brightness.light);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: BookListItem(
            onTap: () => taps++,
            child: const BookListTile(cover: SizedBox(), title: 'Row title'),
          ),
        ),
      ),
    );
    BoxDecoration tint() =>
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration!
            as BoxDecoration;
    Color? titleColor() => tester
        .widget<AnimatedDefaultTextStyle>(
          find
              .ancestor(
                of: find.text('Row title'),
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        )
        .style
        .color;
    // Material's own overlay is switched off.
    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(
      ink.overlayColor?.resolve({WidgetState.hovered}),
      Colors.transparent,
    );
    expect(tint().color!.a, 0);
    expect(titleColor(), theme.colorScheme.onSurface);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(BookListItem)));
    await tester.pumpAndSettle();
    final hover = tint().color!;
    expect(hover.a, greaterThan(0));
    expect(hover.withValues(alpha: 1), theme.colorScheme.primary);
    expect(tint().borderRadius, BorderRadius.circular(ShioriShape.control));
    expect(titleColor(), theme.colorScheme.primary);

    final press = await tester.startGesture(
      tester.getCenter(find.byType(BookListItem)),
    );
    await tester.pumpAndSettle();
    expect(tint().color!.a, greaterThan(hover.a));
    await press.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(tint().color!.a, 0);

    // Content sits inside the tint's edge rather than touching it.
    final row = tester.getRect(find.byType(BookListItem));
    final content = tester.getRect(find.byType(BookListTile));
    expect(content.left - row.left, BookListItem.inset);
  });
}
