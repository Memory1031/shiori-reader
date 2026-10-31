import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/updates/release_notes_preview.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    String notes, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: ListView(
              children: [
                Center(
                  child: SizedBox(
                    width: 280,
                    child: ReleaseNotesPreview(notes: notes),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renders Markdown formatting without loading images or opening links',
    (tester) async {
      await mount(tester, '''
## Changes

- **EPUB** progress
- *Windows* layout
- `ReaderPosition` fix

[External](https://example.invalid/track)
![remote](https://example.invalid/track.png)
![local](file:///private/image.png)
![asset](resource:assets/image.png)

<img src="https://example.invalid/html.png" />
<script>alert('test')</script>
''');
      expect(find.text('Changes', findRichText: true), findsOneWidget);
      expect(find.text('EPUB progress', findRichText: true), findsOneWidget);
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdown.onTapLink, isNull);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      final spans = tester.widgetList<RichText>(find.byType(RichText));
      final styles = <TextSpan>[];
      void collect(InlineSpan span) {
        if (span is TextSpan) {
          styles.add(span);
          for (final child in span.children ?? <InlineSpan>[]) {
            collect(child);
          }
        }
      }

      for (final text in spans) {
        collect(text.text);
      }
      expect(
        styles.any(
          (s) => s.text == 'EPUB' && s.style?.fontWeight == FontWeight.bold,
        ),
        isTrue,
      );
      expect(
        styles.any(
          (s) => s.text == 'Windows' && s.style?.fontStyle == FontStyle.italic,
        ),
        isTrue,
      );
      expect(
        styles.any(
          (s) =>
              s.text == 'ReaderPosition' && s.style?.fontFamily == 'monospace',
        ),
        isTrue,
      );
      await mount(tester, '[External](https://example.invalid/track)');
      await tester.tap(
        find.text('External', findRichText: true),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '$brightness preview stays bounded for long lists, code and tables',
      (tester) async {
        await mount(
          tester,
          '''
## Update

```dart
final value = '${'x' * 200}';
```

| Platform | Status |
| --- | --- |
| Android | Ready |

${List.generate(80, (i) => '- Change $i').join('\n')}
''',
          brightness: brightness,
          scale: 1.5,
        );
        expect(
          tester.getSize(find.byType(ClipRect).last).height,
          lessThanOrEqualTo(330),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Read full notes'), findsOneWidget);
        await mount(tester, 'Short note', brightness: brightness);
        expect(
          tester.getSize(find.byType(ReleaseNotesPreview)).height,
          lessThan(60),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('update-notes-toggle')), findsNothing);
      },
    );
  }

  testWidgets('expands in the page and collapses back to its preview', (
    tester,
  ) async {
    final notes =
        '${List.generate(30, (i) => '- Change $i').join('\n')}\n\nLast change';
    await mount(tester, notes);
    final preview = find.byType(ReleaseNotesPreview);
    final toggle = find.byKey(const ValueKey('update-notes-toggle'));
    final collapsedHeight = tester.getSize(preview).height;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.getSize(preview).height, greaterThan(collapsedHeight));
    expect(find.text('Collapse notes'), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    final last = find.text('Last change', findRichText: true);
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(last).dy, greaterThanOrEqualTo(0));
    expect(tester.getBottomRight(last).dy, lessThanOrEqualTo(600));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.getSize(preview).height, collapsedHeight);
    expect(toggle.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(preview).dy, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await mount(tester, '$notes\n\nA different release');
    expect(find.text('Read full notes'), findsOneWidget);
    expect(tester.getSize(preview).height, collapsedHeight);
  });
}
