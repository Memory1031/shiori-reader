import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/novel_detail/detail_sections.dart';
import 'package:shiori/features/novel_detail/catalog_view.dart';
import 'package:shiori/features/novel_detail/volume_preview.dart';

import 'catalog_test.dart' show app, catalog;
import 'detail_test.dart' show Repo, detail;

class PreviewRepo extends Repo {
  PreviewRepo(this.value);
  final Catalog value;
  final modes = <ReadMode>[];
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    modes.add(mode);
    return Success(
      LoadResult(
        value: value,
        origin: LoadOrigin.local,
        fetchedAt: DateTime.utc(2026),
      ),
    );
  }
}

void main() {
  testWidgets('synopsis and tags expand only when truncated and can collapse', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = detail(rich: true).value;
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: Column(
            children: [
              DetailBookHeader(detail: data),
              DetailSynopsis(text: data.synopsis),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final entry in [
      (key: 'detail-tags-toggle', text: data.tags.join(' · '), lines: 2),
      (key: 'detail-synopsis-toggle', text: data.synopsis, lines: 5),
    ]) {
      final toggle = find.byKey(ValueKey(entry.key));
      expect(tester.widget<Text>(find.text(entry.text)).maxLines, entry.lines);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(entry.text)).maxLines, isNull);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(entry.text)).maxLines, entry.lines);
    }
    await tester.pumpWidget(app(const DetailSynopsis(text: 'Short synopsis.')));
    expect(find.byKey(const ValueKey('detail-synopsis-toggle')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preview is bounded, shares the page scroll and preserves full catalog navigation',
    (tester) async {
      final data = catalog(count: 4);
      final repo = PreviewRepo(data);
      addTearDown(repo.events.close);
      ChapterKey? selected;
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: VolumePreview(
              novel: data.novelKey,
              repository: repo,
              onChapter: (key) => selected = key,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final preview = find.byType(VolumePreview);
      expect(
        find.descendant(of: preview, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(find.text('Same title'), findsNWidgets(5));
      expect(find.text('Untitled volume'), findsNWidgets(2));
      expect(repo.modes, [ReadMode.cacheOnly]);
      final fifth = data.flatChapters.elementAt(4);
      final lastPreview = find.byKey(ValueKey(('preview-chapter', fifth.key)));
      await tester.ensureVisible(lastPreview);
      await tester.tap(lastPreview);
      expect(selected, fifth.key);
      final all = find.byKey(const ValueKey('detail-catalog'));
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(find.byType(CatalogScreen), findsOneWidget);
      final last = data.flatChapters.last.key;
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(last)),
        200,
        scrollable: find.descendant(
          of: find.byType(CatalogView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(ValueKey(last)));
      await tester.pumpAndSettle();
      expect(selected, last);
      expect(find.byType(CatalogScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
