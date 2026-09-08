import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/local_books/local_catalog.dart';
import '../../data/local/support/epub_fixtures.dart';
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;

class MemoryBooks implements LocalBookStore {
  MemoryBooks(this.record);
  final LocalBookRecord record;
  Completer<void>? delay;
  @override
  Future<Result<LocalBookRecord?>> read(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    await delay?.future;
    if (cancellation.isCancelled) {
      return Failure(
        AppFailure(kind: FailureKind.cancelled, operation: Operation.chapter),
      );
    }
    return Success(record);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  for (final mode in ReaderMode.values) {
    testWidgets(
      'local nested fragment, same chapter jump, previous/next and resume in ${mode.name}',
      (tester) async {
        final files = epubFiles();
        files['OPS/text/a.xhtml'] = utf8.encode(
          '<html><body><h1>First</h1><p id="one">Before target</p>${List.generate(50, (i) => '<p>Padding $i. ${'Offline body. ' * 10}</p>').join()}<h2 id="two">Anchor destination</h2><p>After target</p></body></html>',
        );
        final key = LocalBookIdentity.book('a' * 64);
        final content = EpubParser(
          zipFiles(files),
          key,
          'offline.epub',
        ).parse().content;
        final store = MemoryBooks(
          LocalBookRecord(
            content: content,
            format: LocalBookFormat.epub,
            importedAt: DateTime.now(),
          ),
        );
        final repository = LocalReadingRepository(
          local: store,
          online: ForbiddenOnline(),
        );
        final library = FixtureLibraryRepository();
        final settings = FixtureSettingsStore();
        await settings.save(
          ReaderSettings(mode: mode, controlsHintSeen: true),
          cancellation: CancellationSource().token,
        );
        Widget app({String? anchor}) => ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: content.chapters.first.key,
              repository: repository,
              library: library,
              settings: settings,
              initialBlockKey: anchor,
            ),
          ),
        );
        ReaderContentView view() =>
            tester.widget<ReaderContentView>(find.byType(ReaderContentView));
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        // Tap the visible catalog action: local books bypass article headings.
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Book contents'));
        await tester.pumpAndSettle();
        expect(find.byType(LocalNavigationView), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('In-volume contents'), findsNothing);
        expect(
          tester
              .widget<ListTile>(find.byKey(const ValueKey(('local-toc', 2))))
              .selected,
          isTrue,
        );
        await tester.tap(find.text('第二段'));
        await tester.pumpAndSettle();
        final target = content.navigation.last.children.first;
        expect(view().content.key, target.chapterKey);
        expect(view().initialPosition!.blockKey, target.blockKey);
        expect(
          find.textContaining('Anchor destination', findRichText: true),
          findsWidgets,
        );
        await tester.pump(const Duration(seconds: 1));
        await view().session!.flushProgress();
        final saved =
            (await library.getProgress(
                      key,
                      cancellation: CancellationSource().token,
                    )
                    as Success<ReadingProgress?>)
                .value!;
        expect(saved.position.blockIndex, greaterThan(45));
        // Recreate the screen: continue reading uses the persisted semantic position.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(view().initialPosition!.blockIndex, saved.position.blockIndex);
        view().onNextChapter!();
        await tester.pumpAndSettle();
        expect(view().content.key, content.chapters[1].key);
        view().onPreviousChapter!();
        await tester.pumpAndSettle();
        expect(view().content.key, content.chapters.first.key);
        view().onCatalog!();
        await tester.pumpAndSettle();
        await tester.tap(find.text('缺锚点'));
        await tester.pumpAndSettle();
        expect(view().initialPosition!.blockIndex, 0);
        // Late local reads must not update a disposed reader.
        store.delay = Completer<void>();
        view().onNextChapter!();
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        store.delay!.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await library.close();
      },
    );
  }
}
