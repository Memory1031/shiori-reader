import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_source.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_identity.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_api.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';
import '../../network/network_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RequestScheduler scheduler;
  late LightNovelSource source;
  late TestAdapter api, media;
  late Map<String, dynamic> metadata;
  final token = CancellationSource().token;
  final cover = MediaRef(
    sourceId: lightNovelSourceId,
    mediaId: 'cover:v1:31607',
  );
  final png = File(
    'test/fixtures/lightnovel/assets/synthetic-checker.png',
  ).readAsBytesSync();
  late AppLogger logger;
  void create() {
    api = TestAdapter(
      (_) => response(
        bytes: utf8.encode(jsonEncode({'code': 0, 'data': metadata})),
      ),
    );
    media = TestAdapter(
      (_) => response(
        bytes: png,
        headers: {
          'content-type': ['image/png'],
        },
      ),
    );
    source = LightNovelSource(
      scheduler: scheduler,
      logger: logger,
      adapter: api,
      mediaAdapterFactory: () => media,
    );
  }

  setUp(() {
    scheduler = RequestScheduler(startInterval: Duration.zero);
    logger = AppLogger(release: false);
    metadata = {
      'book_id': 31607,
      'cover_url': 'https://api.lightnovel.fun/synthetic.png?m=old',
    };
    create();
  });
  tearDown(() {
    source.close();
    scheduler.close();
  });
  Future<SourceMediaBody> open(
    MediaRef ref, {
    int max = 1024 * 1024,
    CancellationToken? cancellation,
  }) async =>
      (await source.openMedia(
                ref,
                maxBytes: max,
                cancellation: cancellation ?? token,
              )
              as Success<SourceMediaBody>)
          .value;
  test(
    'serialized cover ref survives fresh Source; current signature only and real PNG decode',
    () async {
      final ref = MediaRef.fromJson(jsonDecode(jsonEncode(cover.toJson())));
      source.close();
      metadata['cover_url'] = 'https://api.lightnovel.fun/synthetic.png?m=new';
      create();
      final body = await open(ref);
      final bytes = <int>[];
      await for (final chunk in body.chunks) {
        bytes.addAll((chunk as Success<List<int>>).value);
      }
      expect(bytes, png);
      expect(media.requests.single.uri.query, 'm=new');
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 2);
      frame.image.dispose();
      codec.dispose();
      expect(logger.events.toString(), isNot(contains('m=new')));
      await body.close();
      await body.close();
    },
  );
  test(
    'chapter ref resolves fresh HTML after reconstruction, changed host does not fetch',
    () async {
      metadata = {
        'book_id': 31607,
        'chapter_id': 309555,
        'title': 'Synthetic',
        'locked': 0,
        'body_snapshot': {
          'body_html': '<img src="https://api.lightnovel.fun/a.png?m=old">',
        },
      };
      final chapter =
          (await source.getChapter(
                    lightNovelChapterKey(lightNovelKey(31607), 309555),
                    cancellation: token,
                  )
                  as Success<ChapterContent>)
              .value;
      final ref = (chapter.blocks.single as ImageBlock).media;
      source.close();
      metadata['body_snapshot']['body_html'] =
          '<img src="https://api.lightnovel.fun/a.png?m=new">';
      create();
      final body = await open(ref);
      await body.close();
      expect(media.requests.single.uri.query, 'm=new');
      metadata['body_snapshot']['body_html'] =
          '<img src="https://www.lightnovel.fun/a.png?m=new">';
      expect(
        (await source.openMedia(ref, maxBytes: 10000, cancellation: token)
                as Failure)
            .failure
            .kind,
        FailureKind.notFound,
      );
      expect(media.requests.length, 1);
    },
  );
  test(
    'relative current cover accepted; unknown host and credentials rejected',
    () async {
      metadata['cover_url'] = '/synthetic.png';
      final body = await open(cover);
      await body.close();
      expect(media.requests.single.uri.host, 'www.lightnovel.fun');
      for (final raw in [
        'https://evil.test/a',
        'http://api.lightnovel.fun/a',
        'https://u:p@api.lightnovel.fun/a',
      ]) {
        metadata['cover_url'] = raw;
        expect(
          await source.openMedia(cover, maxBytes: 1000, cancellation: token),
          isA<Failure>(),
        );
      }
      expect(media.requests.length, 1);
    },
  );
  test('redirect, bad MIME and byte limit stop without retries', () async {
    for (final mode in ['redirect', 'mime', 'size']) {
      source.close();
      create();
      final adapter = TestAdapter(
        (_) => mode == 'redirect'
            ? response(
                status: 302,
                headers: {
                  'location': ['https://evil.test/x'],
                },
              )
            : response(
                bytes: png,
                headers: {
                  'content-type': [mode == 'mime' ? 'text/html' : 'image/png'],
                },
              ),
      );
      media = adapter;
      final result = await source.openMedia(
        cover,
        maxBytes: mode == 'size' ? 1 : 10000,
        cancellation: token,
      );
      expect(result, isA<Failure>());
      expect(adapter.requests.length, 1);
      expect(
        adapter.requests.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('cookie')),
      );
    }
  });
  test(
    'invalid ref and pre-cancel do no IO; cancelled delivered body emits terminal failure',
    () async {
      expect(
        await source.openMedia(
          MediaRef(
            sourceId: lightNovelSourceId,
            mediaId: 'https://secret.test',
          ),
          maxBytes: 1000,
          cancellation: token,
        ),
        isA<Failure>(),
      );
      final caller = CancellationSource();
      caller.cancel();
      expect(
        (await source.openMedia(
                  cover,
                  maxBytes: 1000,
                  cancellation: caller.token,
                )
                as Failure)
            .failure
            .isCancellation,
        true,
      );
      expect(api.requests, isEmpty);
      final active = CancellationSource();
      final body = await open(cover, cancellation: active.token);
      active.cancel();
      final chunks = await body.chunks.toList();
      expect(chunks.length, 1);
      expect((chunks.single as Failure).failure.isCancellation, true);
    },
  );
  test('locked or missing locator does not issue image request', () async {
    metadata = {
      'book_id': 31607,
      'chapter_id': 309555,
      'title': 'Synthetic',
      'locked': 0,
      'body_snapshot': {
        'body_html': '<img src="https://api.lightnovel.fun/a.png">',
      },
    };
    final chapter =
        (await source.getChapter(
                  lightNovelChapterKey(lightNovelKey(31607), 309555),
                  cancellation: token,
                )
                as Success<ChapterContent>)
            .value;
    final ref = (chapter.blocks.single as ImageBlock).media;
    metadata['locked'] = 1;
    expect(
      (await source.openMedia(ref, maxBytes: 1000, cancellation: token)
              as Failure)
          .failure
          .kind,
      FailureKind.accessRestricted,
    );
    expect(media.requests, isEmpty);
  });
}
