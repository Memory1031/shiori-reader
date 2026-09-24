import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/novel_detail/detail_sections.dart';
import 'package:shiori/features/novel_detail/catalog_view.dart';
import 'package:shiori/features/novel_detail/volume_preview.dart';
import 'package:shiori/features/local_books/local_catalog.dart';

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

class LocalPreviewRepo extends PreviewRepo
    implements LocalNavigationRepository {
  LocalPreviewRepo(super.value, this.entries);
  final List<LocalNavigationEntry> entries;

  @override
  Future<Result<List<LocalNavigationEntry>>> loadNavigation(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async => Success(entries);
}

void main() {
  testWidgets(
    'local detail previews NCX labels and preserves target position',
    (tester) async {
      final novel = LocalBookIdentity.book('a' * 64);
      final first = LocalBookIdentity.chapter(novel, 'epub:first.xhtml');
      final second = LocalBookIdentity.chapter(novel, 'epub:second.xhtml');
      final data = Catalog(
        novelKey: novel,
        volumes: [
          Volume(
            groupId: 'epub',
            isSynthetic: true,
            chapters: [
              Chapter(
                key: first,
                title: 'Repeated book title',
                ordinal: 0,
                volumeGroupId: 'epub',
              ),
              Chapter(
                key: second,
                title: 'Repeated book title',
                ordinal: 1,
                volumeGroupId: 'epub',
              ),
            ],
          ),
        ],
      );
      final entries = [
        LocalNavigationEntry(title: '目录', chapterKey: first),
        LocalNavigationEntry(title: '第１话 小澄同学', chapterKey: first),
        LocalNavigationEntry(
          title: '第２话 矮个子辣妹同学',
          chapterKey: second,
          blockKey: 'chapter-2-start',
        ),
        LocalNavigationEntry(title: '第３话 体育仓库', chapterKey: second),
        LocalNavigationEntry(title: '幕间', chapterKey: second),
        LocalNavigationEntry(title: '预览范围外', chapterKey: second),
      ];
      final repo = LocalPreviewRepo(data, entries);
      addTearDown(repo.events.close);
      LocalNavigationEntry? selected;
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: VolumePreview(
              novel: novel,
              repository: repo,
              onTarget: (target) => selected = target,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Repeated book title'), findsNothing);
      for (final entry in entries.take(5)) {
        expect(find.text(entry.title), findsOneWidget);
      }
      expect(find.text('预览范围外'), findsNothing);
      await tester.tap(find.byKey(const ValueKey(('preview-local', 2))));
      expect(selected, same(entries[2]));
      expect(selected!.blockKey, 'chapter-2-start');

      await tester.tap(find.byKey(const ValueKey('detail-catalog')));
      await tester.pumpAndSettle();
      expect(find.byType(LocalCatalogScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey(('local-toc', 1))));
      await tester.pumpAndSettle();
      expect(selected, same(entries[1]));
    },
  );

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
