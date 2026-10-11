import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/epub_layout_page.dart';
import 'package:shiori/features/reader/reader_audio.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import '../../data/local/support/synthetic_audio.dart';
import 'audio_test.dart' show AudioImages;

T value<T>(Result<T> result) => (result as Success<T>).value;

void main() {
  testWidgets(
    'production special audio import reopens as one playable native control',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
      }

      Future<void> drain(Future<void> future) async {
        var done = false;
        future.whenComplete(() => done = true);
        for (var i = 0; i < 100 && !done; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(done, isTrue, reason: 'Pending test-clock IO did not finish');
        await future;
      }

      final cancellation = CancellationSource();
      late Directory root;
      late ManagedLocalBooks store;
      late UserDatabase db;
      late LocalBookRecord record;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('shiori-special-audio-');
        final paths = AppPaths(
          support: Directory('${root.path}/support'),
          temporary: root,
          environment: StorageEnvironment.development,
        );
        await paths.prepare();
        db = UserDatabase(NativeDatabase(paths.userDatabase));
        store = value(await ManagedLocalBooks.open(paths, db));
        record = value(
          await store.importBook(
            bytes: Stream.value(
              audioEpubBytes(
                '<p style="transform:rotate(2deg)">Synthetic audio page.</p>'
                '<audio controls src="../audio/test.wav"></audio>'
                '<p>${'Readable bounded tail. ' * 65}</p>',
              ),
            ),
            format: LocalBookFormat.epub,
            cancellation: cancellation.token,
            parse: (session) => const BookDecoder().decode(
              session,
              format: LocalBookFormat.epub,
              filename: 'synthetic.epub',
              cancellation: cancellation.token,
              chooseEncoding: (_) async => TxtEncoding.utf8,
            ),
          ),
        );
        await store.close();
        store = value(await ManagedLocalBooks.open(paths, db));
        record = value(
          await store.read(
            record.content.detail.summary.key,
            cancellation: cancellation.token,
          ),
        )!;
        expect(
          value(
            await store.loadPagePresentation(
              record.content.chapters.first.key,
              cancellation: cancellation.token,
            ),
          ),
          isNull,
        );
        final audio = record.content.chapters.first.blocks
            .whereType<AudioBlock>()
            .single;
        expect(
          value(
            await store.readMedia(
              audio.media!,
              cancellation: cancellation.token,
            ),
          ),
          syntheticWav(),
        );
      });
      final library = FixtureLibraryRepository(),
          settings = FixtureSettingsStore(),
          factory = AudioImages(),
          boundary = GlobalKey();
      await settings.save(
        ReaderSettings(controlsHintSeen: true),
        cancellation: cancellation.token,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await settle();
        await library.close();
        await drain(store.close());
        await drain(db.close());
        await tester.runAsync(() => root.delete(recursive: true));
      });
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => RepaintBoundary(
              key: boundary,
              child: BookReaderScreen(
                chapter: record.content.chapters.first.key,
                repository: LocalReadingRepository(
                  local: store,
                  online: ForbiddenOnline(),
                ),
                library: library,
                settings: settings,
                images: factory,
                startAtBeginning: true,
              ),
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 40 && find.byType(PagedReaderViewport).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await settle();
      expect(find.byType(EpubLayoutPage), findsNothing);
      expect(find.byType(ReaderAudioControl), findsOneWidget);
      expect(factory.creates, 0);
      final output = Platform.environment['SHIORI_REVIEW_SCREENSHOTS'];
      if (output != null) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/special-audio-native.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      factory.player.pending = Completer<Result<void>>();
      final button = find.descendant(
        of: find.byType(ReaderAudioControl),
        matching: find.byType(IconButton),
      );
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(factory.creates, 1);
      expect(factory.player.plays, 1);
      factory.player.pending!.complete(const Success<void>(null));
      await tester.pumpAndSettle();
      final viewport = tester.widget<PagedReaderViewport>(
        find.byType(PagedReaderViewport),
      );
      await drain(viewport.controller.next());
      await settle();
      expect(factory.player.stops, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(factory.player.closes, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
