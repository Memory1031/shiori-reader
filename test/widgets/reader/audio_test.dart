import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_audio.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import '../../data/local/support/synthetic_audio.dart';
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import 'local_reading_test.dart' show MemoryBooks;

class FakePlayback implements AudioPlayback {
  final events = StreamController<AudioPlaybackState>.broadcast();
  int plays = 0, pauses = 0, resumes = 0, stops = 0, closes = 0;
  bool fail = false;
  MediaRef? media;
  Completer<Result<void>>? pending;
  @override
  Stream<AudioPlaybackState> get states => events.stream;
  @override
  Future<Result<void>> play(MediaRef media, AudioFormat format) async {
    plays++;
    this.media = media;
    return pending?.future ??
        (fail
            ? Failure(
                AppFailure(kind: FailureKind.parse, operation: Operation.media),
              )
            : const Success<void>(null));
  }

  @override
  Future<Result<void>> pause() async {
    pauses++;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> resume() async {
    resumes++;
    return const Success<void>(null);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> close() async {
    closes++;
    await events.close();
  }
}

class AudioImages implements ImageRepository, AudioPlaybackFactory {
  final player = FakePlayback();
  int creates = 0;
  @override
  AudioPlayback createAudioPlayback() {
    creates++;
    return player;
  }

  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => Failure(
    AppFailure(kind: FailureKind.notFound, operation: Operation.media),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final chapter = audioEpub(
    '<p>Self authored audio page.</p><audio controls src="../audio/test.wav"></audio>',
  ).content.chapters.first;
  final audio = chapter.blocks.whereType<AudioBlock>().single;
  test(
    'controller opens lazily, pauses, resumes, switches and releases one chapter player',
    () async {
      final factory = AudioImages(),
          controller = ReaderAudioController(factory);
      expect(factory.creates, 0);
      await controller.toggle(audio);
      expect(controller.state, AudioPlaybackState.playing);
      await controller.toggle(audio);
      expect(factory.player.pauses, 1);
      await controller.toggle(audio);
      expect(factory.player.resumes, 1);
      final next = audio.withOccurrence(1);
      await controller.toggle(next);
      expect(factory.player.plays, 2);
      expect(factory.creates, 1);
      factory.player.events.add(AudioPlaybackState.completed);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, AudioPlaybackState.completed);
      await controller.toggle(next);
      expect(factory.player.plays, 3);
      controller.stop();
      expect(controller.selected, isNull);
      expect(factory.player.stops, 1);
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(factory.player.closes, 1);
    },
  );
  test('failure retries and stop invalidates a late completion', () async {
    final factory = AudioImages()..player.fail = true,
        controller = ReaderAudioController(factory);
    await controller.toggle(audio);
    expect(controller.failure, isNotNull);
    factory.player.fail = false;
    await controller.toggle(audio);
    expect(controller.failure, isNull);
    factory.player.pending = Completer();
    final pending = controller.toggle(audio.withOccurrence(1));
    controller.stop();
    factory.player.pending!.complete(const Success<void>(null));
    await pending;
    expect(controller.state, AudioPlaybackState.stopped);
    expect(controller.selected, isNull);
    controller.dispose();
  });
  testWidgets(
    'native audio controls have a bounded tap target and do not autoplay',
    (tester) async {
      final factory = AudioImages(),
          controller = ReaderAudioController(factory);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ShioriApp(
          routes: AppRoutes(
            home: (_) => Scaffold(
              body: ReaderAudioControl(
                block: audio,
                controller: controller,
                enabled: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(factory.creates, 0);
      final button = find.byType(IconButton);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await tester.pumpWidget(
        ShioriApp(
          routes: AppRoutes(
            home: (_) => ReaderAudioControl(
              block: AudioBlock(unavailable: AudioUnavailable.external),
              controller: controller,
              enabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(button).onPressed, isNull);
    },
  );
  testWidgets('pending audio commands keep the button color and icon stable', (
    tester,
  ) async {
    final factory = AudioImages()..player.pending = Completer(),
        controller = ReaderAudioController(factory);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ShioriApp(
        routes: AppRoutes(
          home: (_) => Scaffold(
            body: ReaderAudioControl(
              block: audio,
              controller: controller,
              enabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byType(IconButton);
    final rect = tester.getRect(button);
    await tester.tap(button);
    await tester.pump();
    expect(controller.loading, isTrue);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getRect(button), rect);
    await tester.tap(button);
    expect(factory.player.plays, 1);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    factory.player.pending!.complete(const Success<void>(null));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(tester.getRect(button), rect);
  });
  testWidgets(
    'production pagination stops on background, turn, inactivity and disposal',
    (tester) async {
      final factory = AudioImages(),
          settings = FixtureSettingsStore(),
          viewport = PagedReaderController();
      await settings.save(
        ReaderSettings(controlsHintSeen: true),
        cancellation: CancellationSource().token,
      );
      final long = ChapterContent(
        key: chapter.key,
        title: 'Audio page',
        blocks: [
          ...chapter.blocks,
          ...List.generate(
            60,
            (i) => ParagraphBlock(text: 'Later $i. ${'Readable text. ' * 20}'),
          ),
        ],
      );
      Future<void> mount({bool active = true}) async {
        await tester.pumpWidget(
          ShioriApp(
            routes: AppRoutes(
              home: (_) => ReaderContentView(
                content: long,
                images: factory,
                settings: settings,
                viewportController: viewport,
                active: active,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      expect(factory.creates, 0);
      final buttons = find.byType(ReaderAudioControl);
      expect(buttons, findsWidgets);
      Future<void> play() async {
        await tester.tap(
          find.descendant(of: buttons.first, matching: find.byType(IconButton)),
        );
        await tester.pumpAndSettle();
      }

      await play();
      expect(factory.player.plays, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(factory.player.stops, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await play();
      final turning = viewport.next();
      await tester.pumpAndSettle();
      await turning;
      expect(factory.player.stops, 2);
      final returning = viewport.previous();
      await tester.pumpAndSettle();
      await returning;
      await play();
      await mount(active: false);
      expect(factory.player.stops, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(factory.player.closes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'book reader image cache wrappers retain the separate audio capability',
    (tester) async {
      final parsed = audioEpub(
            '<p>Self authored audio page.</p><p style="text-align:right"><audio controls style="width:1.5em" src="../audio/test.wav"></audio></p>',
          ),
          factory = AudioImages(),
          library = FixtureLibraryRepository(),
          settings = FixtureSettingsStore();
      await settings.save(
        ReaderSettings(controlsHintSeen: true),
        cancellation: CancellationSource().token,
      );
      final store = MemoryBooks(
        LocalBookRecord(
          content: parsed.content,
          format: LocalBookFormat.epub,
          importedAt: DateTime.utc(2026),
        ),
        media: parsed.media,
      );
      await tester.pumpWidget(
        ShioriApp(
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: parsed.content.chapters.first.key,
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
      );
      await tester.pumpAndSettle();
      expect(factory.creates, 0);
      final button = find.descendant(
        of: find.byType(ReaderAudioControl).first,
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);
      final body = tester.getRect(find.byType(ReaderAudioControl).first),
          hit = tester.getRect(button);
      expect(hit.right, closeTo(body.right, 1));
      expect(body.width, greaterThan(200));
      expect(hit.width, greaterThanOrEqualTo(48));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(factory.player.plays, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(factory.player.closes, 1);
      await library.close();
      expect(tester.takeException(), isNull);
    },
  );
}
