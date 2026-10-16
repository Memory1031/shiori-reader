import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/reader_commands.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart'
    show readerColorContrast;
import 'local_search_test.dart' show fonts;
import '../shiori_feedback_test.dart' show feedbackScreenshot;

void main() {
  for (final paper in ['light', 'warm', 'dark', 'accent']) {
    testWidgets(
      'reader popup uses actual $paper palette with readable states',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await fonts(tester);
        final boundary = GlobalKey();
        final settings = ReaderSettings(
          themeMode: paper == 'dark'
              ? ReaderThemeMode.dark
              : ReaderThemeMode.light,
          paper: paper == 'warm' ? ReaderPaper.warm : ReaderPaper.paper,
        );
        final theme = readerTheme(
          settings,
          Brightness.light,
          accent: paper == 'accent' ? AppAccent.warmBrown : AppAccent.teal,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ShioriApp(
              locale: const Locale('en'),
              homeBuilder: (context, _) => Theme(
                data: theme,
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: SafeArea(
                      child: ReaderTopBar(
                        title: 'A quiet chapter',
                        onLeave: () {},
                        menu: const [
                          (ReaderCommand.toggleBookmark, 'Add bookmark'),
                          (ReaderCommand.bookmarks, 'My bookmarks'),
                        ],
                        onMenu: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PopupMenuButton<ReaderCommand>));
        await tester.pumpAndSettle();
        final menu = find.byWidgetPredicate(
          (w) => w is Material && w.elevation == theme.popupMenuTheme.elevation,
        );
        final color = tester.widget<Material>(menu).color!;
        await feedbackScreenshot(tester, boundary, 'popup-$paper');
        expect(
          readerColorContrast(theme.colorScheme.onSurface, color),
          greaterThanOrEqualTo(4.5),
        );
        if (paper == 'warm') {
          expect(
            color,
            isNot(shioriTheme(Brightness.light).colorScheme.surface),
          );
        }
        for (final overlay in [
          theme.hoverColor,
          theme.focusColor,
          theme.highlightColor,
        ]) {
          expect(
            readerColorContrast(
              theme.colorScheme.onSurface,
              Color.alphaBlend(overlay, color),
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
