import 'package:shiori/data/sources/lightnovel/lightnovel_identity.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_api.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_source.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/shared/app_logger.dart';
import '../../network/network_test_support.dart';

void main() {
  test(
    'numeric source identity is stable and invalid IDs never become zero',
    () {
      expect(lightNovelKey(31607), lightNovelKey('31607'));
      expect(
        lightNovelChapterKey(lightNovelKey(31607), 309555).chapterId,
        '309555',
      );
      for (final bad in [
        null,
        0,
        -1,
        1.5,
        '0',
        '01',
        '',
        'https://example.test',
        ' 1',
      ]) {
        expect(() => lightNovelRemoteId(bad), throwsFormatException);
      }
    },
  );
  late RequestScheduler scheduler;
  late AppLogger logger;
  final token = CancellationSource().token;
  setUp(() {
    scheduler = RequestScheduler(startInterval: Duration.zero);
    logger = AppLogger(release: false);
  });
  tearDown(() => scheduler.close());
  test(
    'no-op initialization, source construction and unsupported discovery do no IO',
    () async {
      final adapter = TestAdapter((_) => response());
      final api = LightNovelApi(
        scheduler: scheduler,
        logger: logger,
        adapter: adapter,
      );
      for (var i = 0; i < 20; i++) {
        expect(api.ensureSession(Operation.search, token), isA<Success>());
      }
      expect(adapter.requests, isEmpty);
      final source = LightNovelSource(scheduler: scheduler, logger: logger);
      expect(source.descriptor.sourceId.value, 'lightnovel');
      expect(source.descriptor.supportsDiscover, false);
      expect(
        (await source.discover(cancellation: token) as Failure).failure.kind,
        FailureKind.unsupported,
      );
      source.close();
      api.close();
    },
  );
  test(
    'five fixed POST endpoints use verified headers, ignoring cookies across calls and reconstruction',
    () async {
      final adapters = <TestAdapter>[];
      for (var instance = 0; instance < 2; instance++) {
        final adapter = TestAdapter(
          (_) => response(
            bytes: utf8.encode('{"code":0,"data":{"ok":true}}'),
            headers: {
              'set-cookie': ['secret=sentinel'],
            },
          ),
        );
        adapters.add(adapter);
        final api = LightNovelApi(
          scheduler: scheduler,
          logger: logger,
          adapter: adapter,
        );
        final results = await Future.wait(
          LightNovelEndpoint.values.map(
            (endpoint) => api.request(endpoint, {
              'book_id': '31607',
            }, cancellation: token),
          ),
        );
        expect(results.every((r) => r is Success), true);
        expect(adapter.requests.length, 5);
        for (final request in adapter.requests) {
          expect(request.method, 'POST');
          expect(
            request.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('cookie')),
          );
          expect(
            request.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')),
          );
          expect(request.headers['Origin'], 'https://www.lightnovel.fun');
          expect(request.headers['Referer'], 'https://www.lightnovel.fun/');
        }
        api.close();
        expect(adapter.closed, true);
      }
      expect(logger.events.toString(), isNot(contains('sentinel')));
      expect(logger.events.toString(), isNot(contains('31607')));
    },
  );
  for (final status in [401, 403, 429, 503]) {
    test(
      'HTTP $status stops without session recovery or generic replay',
      () async {
        final adapter = TestAdapter((_) => response(status: status));
        final api = LightNovelApi(
          scheduler: scheduler,
          logger: logger,
          adapter: adapter,
        );
        final result = await api.request(
          LightNovelEndpoint.detail,
          {},
          cancellation: token,
        );
        expect(result, isA<Failure>());
        expect(adapter.requests.length, 1);
        if (status == 429) {
          expect(scheduler.cooldown(lightNovelSourceId), isNotNull);
        }
        api.close();
      },
    );
  }
  test(
    'even same-origin verified endpoint redirect stops before second request',
    () async {
      final adapter = TestAdapter(
        (_) => response(
          status: 307,
          headers: {
            'location': [LightNovelEndpoint.chapter.uri.toString()],
          },
        ),
      );
      final api = LightNovelApi(
        scheduler: scheduler,
        logger: logger,
        adapter: adapter,
      );
      final result = await api.request(
        LightNovelEndpoint.detail,
        {},
        cancellation: token,
      );
      expect((result as Failure).failure.kind, FailureKind.accessRestricted);
      expect(adapter.requests.length, 1);
      api.close();
    },
  );
  test(
    'malformed envelopes and unknown nonzero codes never expose messages or retry',
    () async {
      for (final body in [
        'not json',
        '[]',
        '{"code":"0","data":{}}',
        '{"code":0}',
        '{"code":0,"data":[]}',
        '{"code":123,"message":"secret sentinel"}',
      ]) {
        final adapter = TestAdapter((_) => response(bytes: utf8.encode(body)));
        final api = LightNovelApi(
          scheduler: scheduler,
          logger: logger,
          adapter: adapter,
        );
        final result = await api.request(
          LightNovelEndpoint.search,
          {},
          cancellation: token,
        );
        expect(result, isA<Failure>());
        expect(
          (result as Failure).failure.toString(),
          isNot(contains('sentinel')),
        );
        expect(adapter.requests.length, 1);
        api.close();
      }
    },
  );
  test(
    'pre-cancellation and expired deadline do not dispatch; close aborts in-flight',
    () async {
      final pending = Completer<void>();
      final started = Completer<void>();
      final adapter = TestAdapter((_) async {
        started.complete();
        await pending.future;
        return response(bytes: utf8.encode('{"code":0,"data":{}}'));
      });
      final api = LightNovelApi(
        scheduler: scheduler,
        logger: logger,
        adapter: adapter,
      );
      final cancelled = CancellationSource()..cancel();
      expect(
        (await api.request(
                  LightNovelEndpoint.detail,
                  {},
                  cancellation: cancelled.token,
                )
                as Failure)
            .failure
            .isCancellation,
        true,
      );
      expect(
        (await api.request(
                  LightNovelEndpoint.detail,
                  {},
                  cancellation: token,
                  deadline: DateTime.utc(2000),
                )
                as Failure)
            .failure
            .kind,
        FailureKind.timeout,
      );
      expect(adapter.requests, isEmpty);
      final work = api.request(
        LightNovelEndpoint.detail,
        {},
        cancellation: token,
      );
      await started.future;
      api.close();
      pending.complete();
      expect((await work as Failure).failure.isCancellation, true);
      expect(adapter.closed, true);
    },
  );
}
