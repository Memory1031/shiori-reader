import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/novel_detail/detail_sections.dart';
import 'package:shiori/features/novel_detail/volume_preview.dart';

import 'catalog_test.dart' show app, catalog;
import 'detail_test.dart' show Repo, detail;

/// [preview] on a scrolling page, as the detail pages place it.
Widget page(Widget preview) => app(CustomScrollView(slivers: [preview]));

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
  List<LocalNavigationEntry> entries;
  final catalogEvents = StreamController<Result<LoadResult<Catalog>>>.broadcast(
    sync: true,
  );

  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      catalogEvents.stream;

  void notifyCatalogChanged() => catalogEvents.add(
    Success(
      LoadResult(
        value: value,
        origin: LoadOrigin.local,
        fetchedAt: DateTime.utc(2026),
      ),
    ),
  );

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
      addTearDown(() async {
        await repo.catalogEvents.close();
        await repo.events.close();
      });
      LocalNavigationEntry? selected;
      await tester.pumpWidget(
        page(
          VolumePreview(
            novel: novel,
            repository: repo,
            onTarget: (target) => selected = target,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Repeated book title'), findsNothing);
      // Every entry, with no separate contents screen to open.
      for (final entry in entries) {
        expect(find.text(entry.title), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('detail-catalog')), findsNothing);
      await tester.tap(find.byKey(const ValueKey(('preview-local', 2))));
      expect(selected, same(entries[2]));
      expect(selected!.blockKey, 'chapter-2-start');
      await tester.tap(find.byKey(const ValueKey(('preview-local', 5))));
      expect(selected, same(entries[5]));
    },
  );

  testWidgets('local detail reloads navigation after a catalog change', (
    tester,
  ) async {
    final novel = LocalBookIdentity.book('b' * 64);
    final chapter = LocalBookIdentity.chapter(novel, 'epub:first.xhtml');
    final data = Catalog(
      novelKey: novel,
      volumes: [
        Volume(
          groupId: 'epub',
          isSynthetic: true,
          chapters: [
            Chapter(
              key: chapter,
              title: 'Unchanged spine title',
              ordinal: 0,
              volumeGroupId: 'epub',
            ),
          ],
        ),
      ],
    );
    final repo = LocalPreviewRepo(data, [
      LocalNavigationEntry(title: 'Old NCX label', chapterKey: chapter),
    ]);
    addTearDown(() async {
      await repo.catalogEvents.close();
      await repo.events.close();
    });
    await tester.pumpWidget(
      page(VolumePreview(novel: novel, repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Old NCX label'), findsOneWidget);

    // A reparse can change navigation while the spine catalog stays identical.
    repo.entries = [
      LocalNavigationEntry(title: 'New NCX label', chapterKey: chapter),
    ];
    repo.notifyCatalogChanged();
    await tester.pumpAndSettle();
    expect(find.text('Old NCX label'), findsNothing);
    expect(find.text('New NCX label'), findsOneWidget);
  });

  testWidgets('local preview falls back to chapter selection', (tester) async {
    final novel = LocalBookIdentity.book('c' * 64);
    final chapter = LocalBookIdentity.chapter(novel, 'epub:first.xhtml');
    final data = Catalog(
      novelKey: novel,
      volumes: [
        Volume(
          groupId: 'epub',
          isSynthetic: true,
          chapters: [
            Chapter(
              key: chapter,
              title: 'Spine title',
              ordinal: 0,
              volumeGroupId: 'epub',
            ),
          ],
        ),
      ],
    );
    final repo = LocalPreviewRepo(data, [
      LocalNavigationEntry(
        title: 'NCX chapter',
        chapterKey: chapter,
        blockKey: 'chapter-start',
      ),
    ]);
    addTearDown(() async {
      await repo.catalogEvents.close();
      await repo.events.close();
    });
    ChapterKey? selected;
    await tester.pumpWidget(
      page(
        VolumePreview(
          novel: novel,
          repository: repo,
          onChapter: (key) => selected = key,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(('preview-local', 0))));
    expect(selected, chapter);
  });

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

  testWidgets('the catalog lists every chapter in the page scroll', (
    tester,
  ) async {
    final data = catalog(count: 4);
    final repo = PreviewRepo(data);
    addTearDown(repo.events.close);
    ChapterKey? selected;
    await tester.pumpWidget(
      page(
        VolumePreview(
          novel: data.novelKey,
          repository: repo,
          onChapter: (key) => selected = key,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(VolumePreview),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    expect(find.text('Same title'), findsNWidgets(8));
    expect(find.text('Untitled volume'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('detail-catalog')), findsNothing);
    expect(repo.modes, [ReadMode.cacheOnly]);
    final last = data.flatChapters.last;
    final row = find.byKey(ValueKey(('preview-chapter', last.key)));
    await tester.ensureVisible(row);
    await tester.tap(row);
    expect(selected, last.key);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long catalog builds its rows as they scroll into view', (
    tester,
  ) async {
    final data = catalog(count: 1000);
    final repo = PreviewRepo(data);
    addTearDown(repo.events.close);
    ChapterKey? selected;
    await tester.pumpWidget(
      page(
        VolumePreview(
          novel: data.novelKey,
          repository: repo,
          onChapter: (key) => selected = key,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final built = find.text('Same title', skipOffstage: false);
    expect(built.evaluate().length, lessThan(40));
    final last = data.flatChapters.last;
    expect(data.flatChapters, hasLength(2000));
    final row = find.byKey(ValueKey(('preview-chapter', last.key)));
    await tester.scrollUntilVisible(
      row,
      5000,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(built.evaluate().length, lessThan(40));
    await tester.tap(row);
    expect(selected, last.key);
    expect(repo.modes, [ReadMode.cacheOnly]);
    expect(tester.takeException(), isNull);
  });
}
