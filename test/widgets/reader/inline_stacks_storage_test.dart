import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_inline_stack.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import '../../data/local/support/epub_fixtures.dart';
import '../../data/local/epub_inline_stacks_test.dart' show stackStyle;

T value<T>(Result<T> result) => (result as Success<T>).value;
void main() {
  testWidgets(
    'parser to managed manifest to cold Reader preserves layout and interior position',
    (tester) async {
      late Directory temp;
      late AppPaths paths;
      late UserDatabase db;
      late ManagedLocalBooks store;
      late ChapterContent cold;
      late LocalBookRecord savedRecord;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('shiori-stack-store-');
        paths = AppPaths(
          support: Directory('${temp.path}/s'),
          temporary: temp,
          environment: StorageEnvironment.development,
        );
        await paths.prepare();
        db = UserDatabase(NativeDatabase(paths.userDatabase));
        store = value(await ManagedLocalBooks.open(paths, db));
        final files = epubFiles();
        files['OPS/text/a.xhtml'] = utf8.encode(
          '<html><body><p>${'合成前文。' * 45}<span style="$stackStyle"><span style="font-size:.68em">SAMPLE</span><br/>示例</span>${'后文。' * 25}</p></body></html>',
        );
        final token = CancellationSource().token;
        final record = value(
          await store.importBook(
            bytes: Stream.value(zipFiles(files)),
            format: LocalBookFormat.epub,
            cancellation: token,
            parse: (s) => const BookDecoder().decode(
              s,
              format: LocalBookFormat.epub,
              filename: 'synthetic.epub',
              cancellation: token,
              chooseEncoding: (_) async => TxtEncoding.utf8,
            ),
          ),
        );
        await store.close();
        await db.close();
        db = UserDatabase(NativeDatabase(paths.userDatabase));
        store = value(await ManagedLocalBooks.open(paths, db));
        final reopened = value(
          await store.read(
            record.content.detail.summary.key,
            cancellation: CancellationSource().token,
          ),
        );
        savedRecord = reopened!;
        cold = reopened.content.chapters.first;
        expect(
          cold.blocks.single.inlineStacks,
          record.content.chapters.first.blocks.single.inlineStacks,
        );
      });
      final b = cold.blocks.single as ParagraphBlock;
      final s = b.inlineStacks.single;
      final anchor = ReaderPosition(
        contentRevision: cold.contentRevision,
        blockKey: b.blockKey,
        blockIndex: 0,
        blockFraction: (s.separator + 1) / b.text.runes.length,
        chapterFraction: (s.separator + 1) / b.text.runes.length,
      );
      final controller = PagedReaderController();
      Widget view(ReaderPosition position) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReaderContentView(
          content: cold,
          viewportController: controller,
          initialPosition: position,
        ),
      );
      await tester.pumpWidget(view(anchor));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderInlineStack), findsOneWidget);
      expect(controller.usedFallback, isFalse);
      final captured = controller.capture()!;
      expect(captured.blockFraction, closeTo(anchor.blockFraction, 1e-8));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      final restored = await tester.runAsync(() async {
        final library = LocalLibraryRepository(db);
        final token = CancellationSource().token;
        final generation = value(
          await library.beginProgressSession(
            cold.key.novelKey,
            cancellation: token,
          ),
        );
        value(
          await library.saveProgress(
            ReadingProgress(
              snapshot: savedRecord.content.detail.summary,
              chapterKey: cold.key,
              chapterOrdinalSnapshot: 0,
              catalogRevision: savedRecord.content.catalog.revision,
              position: captured,
              completed: false,
              lastReadAt: DateTime.utc(2026),
            ),
            stamp: ProgressWriteStamp(generation: generation, sequence: 0),
            cancellation: token,
          ),
        );
        await store.close();
        await db.close();
        db = UserDatabase(NativeDatabase(paths.userDatabase));
        store = value(await ManagedLocalBooks.open(paths, db));
        cold = value(
          await store.read(cold.key.novelKey, cancellation: token),
        )!.content.chapters.first;
        return value(
          await LocalLibraryRepository(
            db,
          ).getProgress(cold.key.novelKey, cancellation: token),
        )!.position;
      });
      await tester.pumpWidget(view(restored!));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderInlineStack), findsOneWidget);
      expect(controller.capture(), captured);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await store.close();
        await db.close();
        await temp.delete(recursive: true);
      });
    },
  );
}
