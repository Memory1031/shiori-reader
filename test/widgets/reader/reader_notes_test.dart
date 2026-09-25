import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/local_content_links.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_notes.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

final _here = fixtureChapterKey(FixtureScenario.shortChapter);
final _there = ChapterKey(novelKey: _here.novelKey, chapterId: 'two');
final _unnamed = ChapterKey(novelKey: _here.novelKey, chapterId: 'three');

LocalContentLink _note(String label, String text) => LocalContentLink(
  source: _here,
  sourceBlockKey: 'b0',
  label: label,
  sourceOffset: 3,
  target: _here,
  footnoteText: text,
);

LocalContentLink _link(String label, {ChapterKey? target}) => LocalContentLink(
  source: _here,
  sourceBlockKey: 'b0',
  label: label,
  sourceOffset: 0,
  sourceLength: 2,
  target: target,
  unavailable: target == null ? LocalLinkUnavailable.external : null,
);

Widget _app(Widget Function(BuildContext) home, {ThemeData? theme}) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: Scaffold(body: Builder(builder: home)),
    );

void main() {
  testWidgets('notes read in place; references name where they lead', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final long = List.filled(40, 'A long original annotation.').join(' ');
    final followed = <LocalContentLink>[];
    final links = [
      _note('⁽¹⁾', 'Short note.'),
      _note('[2]', long),
      _link('Same chapter', target: _here),
      _link('Named', target: _there),
      _link('Unnamed', target: _unnamed),
      _link('Outside'),
    ];
    await tester.pumpWidget(
      _app(
        (_) => ReaderNotesPanel(
          links: links,
          current: _here,
          titleOf: (target) => target == _there ? 'Chapter Two' : null,
          onFollow: followed.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chapter notes'), findsOneWidget);
    expect(find.text('Notes · 2'), findsOneWidget);
    expect(find.text('Links · 4'), findsOneWidget);
    // Markers drop their brackets and superscript forms.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Short note.'), findsOneWidget);

    // A long note is clamped until tapped, then shows in full.
    Text body() => tester.widget<Text>(find.text(long));
    expect(body().maxLines, 3);
    await tester.tap(find.text(long));
    await tester.pumpAndSettle();
    expect(body().maxLines, isNull);

    expect(find.text('In this chapter'), findsOneWidget);
    expect(find.text('Chapter Two'), findsOneWidget);
    expect(find.text('Elsewhere in this book'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Outside')).enabled,
      isFalse,
    );
    await tester.tap(find.text('Named'));
    await tester.tap(find.text('Outside'));
    await tester.pump();
    expect(followed.map((link) => link.label), ['Named']);
  });

  testWidgets('the notes sheet takes the theme of the context it opens from', (
    tester,
  ) async {
    const paper = Color(0xfff2e8d5);
    await tester.pumpWidget(
      _app(
        (context) => Theme(
          data: Theme.of(context).copyWith(
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: paper,
            ),
          ),
          child: Builder(
            builder: (reader) => TextButton(
              onPressed: () => showReaderNotes(
                reader,
                links: [_note('1', 'Note.')],
                current: _here,
                titleOf: (_) => null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final sheet = find.ancestor(
      of: find.byType(ReaderNotesPanel),
      matching: find.byType(Material),
    );
    expect(tester.widget<Material>(sheet.first).color, paper);
  });
}
