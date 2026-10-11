import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/media/local_image_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/local_books/local_catalog.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_progress_panel.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import '../../data/local/epub_front_matter_test.dart'
    show frontMatterFiles, page, picture;
import '../../data/local/epub_structure_test.dart' show parse;
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import 'local_reading_test.dart' show MemoryBooks;
import 'logical_progress_test.dart' show openProgress, closeOverlay;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'generated labels follow locale while source labels stay on $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(
          platform == TargetPlatform.android
              ? const Size(440, 900)
              : const Size(1200, 950),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final parsed = parse(
          frontMatterFiles(
            {
              'cover': page('未知', picture, type: 'cover'),
              'title': page('标题', '<p>离线星空 1</p><p>测试作者</p>'),
              'a': page('A', '<p>BODY_MARKER</p>'),
              'sourceCover': page('Cover', picture),
              'sourceTitle': page('Title page', '<p>AUTHORED_MARKER</p>'),
              'aux': page('Unknown', '<p>AUX_MARKER</p>', type: 'preface'),
              'b': page('B', '<p>SECOND_MARKER</p>'),
            },
            spine:
                '<itemref idref="cover"/><itemref idref="title"/><itemref idref="a"/>'
                '<itemref idref="sourceCover"/><itemref idref="sourceTitle"/>'
                '<itemref idref="aux" linear="no"/><itemref idref="b"/>',
          ),
        );
        final book = parsed.content;
        final store = MemoryBooks(
          LocalBookRecord(
            content: book,
            format: LocalBookFormat.epub,
            importedAt: DateTime.utc(2026),
          ),
          media: parsed.media,
        );
        final repo = LocalReadingRepository(
          local: store,
          online: ForbiddenOnline(),
        );
        final settings = FixtureSettingsStore();
        await settings.save(
          ReaderSettings(controlsHintSeen: true, pageTurn: PageTurnStyle.none),
          cancellation: CancellationSource().token,
        );
        final locale = ValueNotifier(const Locale('zh'));
        addTearDown(locale.dispose);
        final routes = AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: book.chapters.first.key,
            repository: repo,
            images: LocalImageRepository(
              local: store,
              online: ForbiddenOnline(),
            ),
            settings: settings,
            startAtBeginning: true,
          ),
        );
        await tester.pumpWidget(
          ValueListenableBuilder<Locale>(
            valueListenable: locale,
            builder: (_, value, _) => ShioriApp(locale: value, routes: routes),
          ),
        );
        Future<void> settle() async {
          for (var i = 0; i < 20; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1)),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.pumpAndSettle();
        }

        ReaderContentView view() => tester
            .widgetList<ReaderContentView>(find.byType(ReaderContentView))
            .firstWhere((v) => v.appearanceActive == true);
        Future<void> change(String language) async {
          final key = view().content.key;
          final anchor = view().viewportController!.capture()!;
          locale.value = Locale(language);
          await settle();
          expect(view().content.key, key);
          expect(
            view().viewportController!.capture()!.blockKey,
            anchor.blockKey,
          );
        }

        void title(String title) {
          expect(
            tester.widget<ReaderTopBar>(find.byType(ReaderTopBar)).title,
            title,
          );
          expect(
            tester
                .widget<ReaderProgressPanel>(find.byType(ReaderProgressPanel))
                .chapterTitle,
            title,
          );
        }

        Future<void> contents() async {
          if (find.byIcon(Icons.list).evaluate().isEmpty) {
            await tester.sendKeyEvent(LogicalKeyboardKey.f2);
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byIcon(Icons.list));
          await tester.pumpAndSettle();
          expect(find.byType(LocalNavigationView), findsOneWidget);
        }

        Future<void> choose(String text) async {
          await contents();
          final row = find.descendant(
            of: find.byType(LocalNavigationView),
            matching: find.text(text),
          );
          await tester.ensureVisible(row);
          await tester.tap(row);
          await settle();
          await openProgress(tester);
        }

        await settle();
        await openProgress(tester);
        title('封面');
        await change('en');
        title('Cover');
        await change('zh');
        title('封面');
        await closeOverlay(tester);

        await choose('扉页');
        expect(view().content.key, book.chapters[1].key);
        title('扉页');
        await change('en');
        title('Title page');
        await change('zh');
        title('扉页');
        await closeOverlay(tester);

        await choose('Title page');
        expect(view().content.key, book.chapters[4].key);
        title('Title page');
        await change('en');
        title('Title page');
        await change('zh');
        title('Title page');
        await closeOverlay(tester);

        await contents();
        final directory = find.byType(LocalNavigationView);
        expect(
          find.descendant(of: directory, matching: find.text('封面')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: directory, matching: find.text('Cover')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: directory, matching: find.text('扉页')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: directory, matching: find.text('Title page')),
          findsOneWidget,
        );
        await tester.tap(
          find.descendant(of: directory, matching: find.text('前言')),
        );
        await settle();
        await openProgress(tester);
        expect(view().content.key, book.chapters[5].key);
        title('前言');
        expect(find.text('当前文档 100%'), findsOneWidget);
        await change('en');
        title('Preface');
        await change('zh');
        title('前言');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
