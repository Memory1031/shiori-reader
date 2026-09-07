import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/novel_detail/catalog_view.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

final novel = NovelKey(sourceId: SourceId('fixture'), novelId: 'book');
Catalog catalog({int count = 4, bool synthetic = false}) => Catalog(
  novelKey: novel,
  volumes: [
    for (var v = 0; v < 2; v++)
      Volume(
        groupId: '$v',
        isSynthetic: synthetic,
        chapters: [
          for (var n = 0; n < count; n++)
            Chapter(
              key: ChapterKey(novelKey: novel, chapterId: '$v:$n'),
              title: 'Same title',
              ordinal: v * count + n,
              volumeGroupId: '$v',
            ),
        ],
      ),
  ],
);
Widget app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);
void main() {
  testWidgets(
    'duplicate titles select identity; collapse, refresh and selection persist',
    (tester) async {
      ChapterKey? selected;
      final data = catalog();
      Widget view(Catalog value) =>
          app(CatalogView(catalog: value, onSelect: (key) => selected = key));
      await tester.pumpWidget(view(data));
      await tester.tap(
        find.byKey(ValueKey(data.volumes.first.chapters[1].key)),
      );
      expect(selected, data.volumes.first.chapters[1].key);
      await tester.pumpWidget(view(catalog()));
      expect(
        tester.widget<ListTile>(find.byKey(ValueKey(selected!))).selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey(('volume', '0'))));
      await tester.pump();
      expect(find.byKey(ValueKey(selected!)), findsNothing);
      expect(find.text('Untitled volume'), findsWidgets);
    },
  );
  testWidgets('synthetic groups omit headers and empty catalog is explicit', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(CatalogView(catalog: catalog(synthetic: true), onSelect: (_) {})),
    );
    expect(find.text('Untitled volume'), findsNothing);
    await tester.pumpWidget(
      app(CatalogView(catalog: catalog(count: 0), onSelect: (_) {})),
    );
    expect(find.text('No chapters available.'), findsOneWidget);
  });
  testWidgets('large catalog only builds visible chapter tiles', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(CatalogView(catalog: catalog(count: 1000), onSelect: (_) {})),
    );
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
  });
}
