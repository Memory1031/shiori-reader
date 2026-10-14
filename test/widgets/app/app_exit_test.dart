import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/app_controller.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_controller.dart';
import 'package:shiori/features/reader/reader_screen.dart';

import '../reader/settings_test.dart' show Store;
import 'appearance_test.dart' show AppStore;
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import '../../data/local/managed_local_books_test.dart' show fixture;

Future<void> exitFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets(
    'passive chapter preload permits exit and preserves the active chapter on restart',
    (tester) async {
      late Directory temp;
      late AppPaths paths;
      late UserDatabase db;
      late ManagedLocalBooks store;
      late LocalBookRecord book;
      var closed = false;
      Future<void> drain(Future<void> future) async {
        var done = false;
        final observed = future.whenComplete(() => done = true);
        for (var i = 0; !done && i < 300; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          done,
          isTrue,
          reason: 'Reader/store shutdown must not wait for window destruction',
        );
        await observed;
      }

      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('exit-local-reader-');
        paths = AppPaths(
          support: temp,
          temporary: temp,
          environment: StorageEnvironment.development,
        );
        await paths.prepare();
        db = UserDatabase(NativeDatabase(paths.userDatabase));
        store =
            (await ManagedLocalBooks.open(paths, db)
                    as Success<ManagedLocalBooks>)
                .value;
        book =
            (await store.importBook(
                      bytes: Stream.value(utf8.encode('durable exit')),
                      format: LocalBookFormat.txt,
                      parse: (s) async {
                        final first = fixture(s);
                        final chapters = [
                          ...first.chapters,
                          ChapterContent(
                            key: LocalBookIdentity.chapter(s.key, 'txt:1'),
                            title: 'Two',
                            blocks: [
                              ParagraphBlock(text: 'Unread next chapter'),
                            ],
                          ),
                        ];
                        return LocalBookContent(
                          detail: first.detail,
                          chapters: chapters,
                          catalog: Catalog(
                            novelKey: s.key,
                            volumes: [
                              Volume(
                                groupId: 'body',
                                chapters: [
                                  for (final (i, chapter) in chapters.indexed)
                                    Chapter(
                                      key: chapter.key,
                                      title: chapter.title,
                                      ordinal: i,
                                      volumeGroupId: 'body',
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                      cancellation: CancellationSource().token,
                    )
                    as Success<LocalBookImportResult>)
                .value
                .book;
      });
      final library = LocalLibraryRepository(db);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        if (!closed) {
          await drain(store.close());
          await drain(db.close());
        }
        await tester.runAsync(() => temp.delete(recursive: true));
      });
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          shutdown: () async {
            await store.close();
            await db.close();
            closed = true;
          },
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: book.content.chapters.first.key,
              repository: LocalReadingRepository(
                local: store,
                online: ForbiddenOnline(),
              ),
              library: library,
              settings: Store()..value = ReaderSettings(controlsHintSeen: true),
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 100 &&
            find
                    .byType(ReaderContentView, skipOffstage: false)
                    .evaluate()
                    .length <
                2;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await exitFrames(tester);
      final views = tester.widgetList<ReaderContentView>(
        find.byType(ReaderContentView, skipOffstage: false),
      );
      expect(views, hasLength(2));
      final candidate = views.singleWhere(
        (view) => view.appearanceActive == false,
      );
      expect(candidate.session!.chapter, book.content.chapters.last.key);
      expect(candidate.session!.progress, isNull);
      expect(candidate.session!.restoreStatus, ReaderRestoreStatus.ready);
      expect(candidate.viewportController!.capture(), isNotNull);
      expect(candidate.onCancelChapter, isNull);
      final session = tester
          .widget<ReaderContentView>(find.byType(ReaderContentView).first)
          .session!;
      await drain(session.flushProgress());
      final content = session.content!;
      session.sampleProgress(
        ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks.first.blockKey,
          blockIndex: 0,
          blockFraction: .5,
          chapterFraction: .5,
        ),
        false,
      );
      AppExitResponse? response;
      await drain(
        tester.binding.handleRequestAppExit().then((value) => response = value),
      );
      expect(response, AppExitResponse.exit);
      expect(closed, isTrue);
      expect(find.byType(SnackBar), findsNothing);
      await tester.runAsync(() async {
        final reopened = UserDatabase(NativeDatabase(paths.userDatabase));
        final reopenedStore =
            (await ManagedLocalBooks.open(paths, reopened)
                    as Success<ManagedLocalBooks>)
                .value;
        ReaderController? restored;
        try {
          final reopenedLibrary = LocalLibraryRepository(reopened);
          final saved =
              (await reopenedLibrary.getProgress(
                        content.key.novelKey,
                        cancellation: CancellationSource().token,
                      )
                      as Success<ReadingProgress?>)
                  .value!;
          expect(saved.position.blockFraction, .5);
          expect(saved.chapterKey, content.key);
          restored = ReaderController(
            repository: LocalReadingRepository(
              local: reopenedStore,
              online: ForbiddenOnline(),
            ),
            library: reopenedLibrary,
            chapter: saved.chapterKey,
          );
          await restored.load();
          expect(restored.status, ReaderStatus.ready);
          expect(restored.content!.key, content.key);
          expect(restored.initialPosition!.blockFraction, .5);
        } finally {
          restored?.onDelete();
          restored?.dispose();
          await restored?.closeReader();
          await reopenedStore.close();
          await reopened.close();
        }
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'exit joins saves and repeated close; readers retire before shutdown',
    (tester) async {
      final env = FixtureEnvironment(scenario: FixtureScenario.longChapter);
      final settings = Store()..value = ReaderSettings(controlsHintSeen: true);
      final appStore = AppStore();
      final app = AppController(settingsStore: appStore);
      final shutdown = Completer<void>();
      var shutdowns = 0;
      var retiredAtShutdown = false;
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          createController: () => app,
          shutdown: () async {
            shutdowns++;
            retiredAtShutdown = find
                .byType(BookReaderScreen)
                .evaluate()
                .isEmpty;
            await shutdown.future;
          },
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: fixtureChapterKey(FixtureScenario.longChapter),
              repository: env.novels,
              library: env.library,
              settings: settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      final view = tester.widget<ReaderContentView>(
        find.byType(ReaderContentView).first,
      );
      final session = view.session!;
      final preferences = view.preferences!;
      final index = session.content!.blocks.length ~/ 2;
      final content = session.content!;
      settings.saving = Completer<void>();
      preferences.update(preferences.value.copyWith(fontSize: 24));
      unawaited(preferences.flush());
      preferences.update(preferences.value.copyWith(fontSize: 30));
      appStore.pending = Completer<Result<void>>();
      app.setAccent(AppAccent.warmBrown);
      app.setAccent(AppAccent.softPink);
      session.sampleProgress(
        ReaderPosition(
          contentRevision: content.contentRevision,
          blockKey: content.blocks[index].blockKey,
          blockIndex: index,
          blockFraction: 0,
          chapterFraction: index / content.blocks.length,
        ),
        false,
      );
      var responses = 0;
      final first = tester.binding.handleRequestAppExit().then((v) {
        responses++;
        return v;
      });
      final repeated = tester.binding.handleRequestAppExit().then((v) {
        responses++;
        return v;
      });
      await tester.pump();
      expect(responses, 0);
      expect(shutdowns, 0);
      appStore.pending!.complete(const Success(null));
      await tester.pump();
      expect(responses, 0);
      settings.saving!.complete();
      await exitFrames(tester);
      expect(settings.value.fontSize, 30);
      expect(appStore.value.accent, AppAccent.softPink);
      expect(
        (await env.library.getProgress(
                  content.key.novelKey,
                  cancellation: CancellationSource().token,
                )
                as Success<ReadingProgress?>)
            .value!
            .position
            .blockIndex,
        index,
      );
      expect(shutdowns, 1);
      expect(responses, 0);
      expect(retiredAtShutdown, isTrue);
      shutdown.complete();
      await tester.pump();
      expect(await first, AppExitResponse.exit);
      expect(await repeated, AppExitResponse.exit);
      await tester.pumpWidget(const SizedBox());
      await env.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final failure in ['settings', 'progress', 'obsolete']) {
    testWidgets(
      '$failure save cancels exit and leaves the reader available',
      (tester) async {
        final env = FixtureEnvironment(scenario: FixtureScenario.longChapter);
        final settings = Store()
          ..value = ReaderSettings(controlsHintSeen: true);
        var shutdowns = 0;
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            shutdown: () async {
              shutdowns++;
            },
            routes: AppRoutes(
              home: (_) => BookReaderScreen(
                chapter: fixtureChapterKey(FixtureScenario.longChapter),
                repository: env.novels,
                library: env.library,
                settings: settings,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        final view = tester.widget<ReaderContentView>(
          find.byType(ReaderContentView).first,
        );
        final session = view.session!;
        final content = session.content!;
        if (failure == 'settings') {
          settings.fail = true;
          view.preferences!.update(
            view.preferences!.value.copyWith(fontSize: 26),
          );
        } else {
          if (failure == 'obsolete') {
            await env.library.beginProgressSession(
              content.key.novelKey,
              cancellation: CancellationSource().token,
            );
          } else {
            env.library.controls.failNext(
              AppFailure(
                kind: FailureKind.database,
                operation: Operation.progressWrite,
              ),
            );
          }
          session.sampleProgress(
            ReaderPosition(
              contentRevision: content.contentRevision,
              blockKey: content.blocks[2].blockKey,
              blockIndex: 2,
              blockFraction: 0,
              chapterFraction: 2 / content.blocks.length,
            ),
            false,
          );
        }
        final exit = tester.binding.handleRequestAppExit();
        await tester.pumpAndSettle();
        expect(await exit, AppExitResponse.cancel);
        expect(shutdowns, 0);
        expect(find.byType(BookReaderScreen), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
        if (failure != 'obsolete') {
          settings.fail = false;
          final retry = tester.binding.handleRequestAppExit();
          await exitFrames(tester);
          expect(await retry, AppExitResponse.exit);
          expect(shutdowns, 1);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await env.close();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
