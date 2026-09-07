import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/network/network_client.dart';
import 'package:shiori/data/network/network_transport.dart';
import 'package:shiori/data/network/network_types.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/shared/app_logger.dart';

import 'network_test_support.dart';

void main() {
  test(
    'one safe retry with injected jitter; unsafe POST and ordinary 4xx stop',
    () {
      for (final (safe, method, status, expected) in [
        (true, HttpMethod.get, 503, 2),
        (false, HttpMethod.post, 503, 1),
        (true, HttpMethod.get, 403, 1),
        (true, HttpMethod.get, 500, 1),
      ]) {
        fakeAsync((async) {
          final epoch = DateTime.utc(2026);
          DateTime now() => epoch.add(async.elapsed);
          final adapter = TestAdapter((_) => response(status: status));
          final transport = ClockTransport(adapter: adapter, now: now);
          final scheduler = RequestScheduler(now: now);
          final client = NetworkClient(
            transport: transport,
            scheduler: scheduler,
            now: now,
            random: (_) => 250,
          );
          Result<NetworkResponse>? result;
          client
              .send(
                NetworkRequest(
                  uri: Uri.parse('https://example.test/read'),
                  operation: Operation.chapter,
                  method: method,
                  safeToRepeat: safe,
                ),
                cancellation: CancellationSource().token,
              )
              .then((v) => result = v);
          async.flushMicrotasks();
          expect(adapter.requests, hasLength(1));
          async.elapse(const Duration(milliseconds: 749));
          expect(adapter.requests, hasLength(1));
          async.elapse(const Duration(milliseconds: 1));
          async.flushMicrotasks();
          expect(adapter.requests, hasLength(expected));
          expect(result, isA<Failure<NetworkResponse>>());
          scheduler.close();
          transport.close();
          async.flushMicrotasks();
          expect(async.pendingTimers, isEmpty);
        });
      }
    },
  );

  test(
    'redirects rewrite methods, rebuild same-origin headers and strip cross-origin secrets',
    () async {
      for (final code in [301, 302, 303, 307, 308]) {
        final adapter = TestAdapter(
          (options) => options.uri.path == '/first'
              ? response(
                  status: code,
                  headers: {
                    'location': ['/last'],
                  },
                )
              : response(),
        );
        final transport = NetworkTransport(
          policy: TestPolicy(headers: {'Authorization': 'SECRET'}),
          logger: AppLogger(),
          adapter: adapter,
        );
        final scheduler = RequestScheduler(startInterval: Duration.zero);
        final client = NetworkClient(
          transport: transport,
          scheduler: scheduler,
        );
        final result = await client.send(
          NetworkRequest(
            uri: Uri.parse('https://example.test/first'),
            operation: Operation.chapter,
            method: HttpMethod.post,
            body: Uint8List.fromList([1]),
          ),
          cancellation: CancellationSource().token,
        );
        expect(result.isSuccess, isTrue);
        expect(adapter.requests.last.method, code >= 307 ? 'POST' : 'GET');
        expect(adapter.requests.last.data, code >= 307 ? isNotNull : isNull);
        expect(adapter.requests.last.headers['Authorization'], 'SECRET');
        scheduler.close();
        transport.close();
      }
      final adapter = TestAdapter(
        (options) => options.uri.host == 'example.test'
            ? response(
                status: 302,
                headers: {
                  'location': ['https://media.test/final'],
                },
              )
            : response(),
      );
      final transport = NetworkTransport(
        policy: TestPolicy(
          headers: {
            'Authorization': 'SECRET',
            'Cookie': 'SECRET',
            'Referer': 'SECRET',
            'X-Token': 'SECRET',
          },
        ),
        logger: AppLogger(),
        adapter: adapter,
      );
      final scheduler = RequestScheduler(startInterval: Duration.zero);
      final result =
          await NetworkClient(transport: transport, scheduler: scheduler).send(
            NetworkRequest(
              uri: Uri.parse('https://example.test/first'),
              operation: Operation.media,
            ),
            cancellation: CancellationSource().token,
          );
      expect(result.isSuccess, isTrue);
      expect(adapter.requests.last.headers.values, isNot(contains('SECRET')));
      scheduler.close();
      transport.close();
    },
  );

  test(
    'redirect downgrade, loops, unapproved hosts, preserved secret body and >5 hops stop',
    () async {
      for (final location in [
        'http://example.test/next',
        '/first',
        'https://unapproved.test/',
        'https://media.test/next',
        '/next',
      ]) {
        var calls = 0;
        final adapter = TestAdapter((_) {
          calls++;
          return response(
            status: 307,
            headers: {
              'location': [location == '/next' ? '/next$calls' : location],
            },
          );
        });
        final transport = NetworkTransport(
          policy: TestPolicy(),
          logger: AppLogger(),
          adapter: adapter,
        );
        final scheduler = RequestScheduler(startInterval: Duration.zero);
        final result =
            await NetworkClient(
              transport: transport,
              scheduler: scheduler,
            ).send(
              NetworkRequest(
                uri: Uri.parse('https://example.test/first'),
                operation: Operation.chapter,
                method: HttpMethod.post,
                body: Uint8List.fromList([1]),
              ),
              cancellation: CancellationSource().token,
            );
        expect((result as Failure).failure.kind, FailureKind.accessRestricted);
        expect(calls, location == '/next' ? 6 : 1);
        scheduler.close();
        transport.close();
      }
    },
  );

  test(
    '429 cools down source, not hosts; no retry and expiry enables manual send',
    () {
      fakeAsync((async) {
        final epoch = DateTime.utc(2026);
        DateTime now() => epoch.add(async.elapsed);
        final adapter = TestAdapter(
          (_) => response(
            status: 429,
            headers: {
              'retry-after': ['3'],
            },
          ),
        );
        final transport = ClockTransport(adapter: adapter, now: now);
        final scheduler = RequestScheduler(now: now);
        final client = NetworkClient(
          transport: transport,
          scheduler: scheduler,
          now: now,
        );
        Future<Result<NetworkResponse>> send(String host) => client.send(
          NetworkRequest(
            uri: Uri.parse('https://$host/read'),
            operation: Operation.media,
            safeToRepeat: true,
          ),
          cancellation: CancellationSource().token,
        );
        Result<NetworkResponse>? result;
        send('example.test').then((v) => result = v);
        send('media.test');
        async.flushMicrotasks();
        expect(
          (result as Failure).failure.retryNotBefore,
          epoch.add(const Duration(seconds: 3)),
        );
        expect(scheduler.queuedCount, 0);
        send('media.test');
        async.flushMicrotasks();
        expect(adapter.requests, hasLength(1));
        async.elapse(const Duration(seconds: 3));
        send('media.test');
        async.flushMicrotasks();
        expect(adapter.requests, hasLength(2));
        scheduler.close();
        transport.close();
        expect(retryAfter(null, epoch), epoch.add(const Duration(seconds: 60)));
        expect(
          retryAfter('Thu, 01 Jan 2026 00:01:00 GMT', epoch),
          epoch.add(const Duration(seconds: 60)),
        );
      });
    },
  );

  test('retry backoff cannot extend total deadline', () {
    fakeAsync((async) {
      final epoch = DateTime.utc(2026);
      DateTime now() => epoch.add(async.elapsed);
      final adapter = TestAdapter((_) => response(status: 503));
      final transport = ClockTransport(adapter: adapter, now: now);
      final scheduler = RequestScheduler(now: now);
      Result<NetworkResponse>? result;
      NetworkClient(
            transport: transport,
            scheduler: scheduler,
            now: now,
            random: (_) => 0,
          )
          .send(
            NetworkRequest(
              uri: Uri.parse('https://example.test/read'),
              operation: Operation.chapter,
              safeToRepeat: true,
            ),
            cancellation: CancellationSource().token,
            deadline: epoch.add(const Duration(milliseconds: 200)),
          )
          .then((v) => result = v);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 200));
      expect((result as Failure).failure.kind, FailureKind.timeout);
      expect(adapter.requests, hasLength(1));
      scheduler.close();
      transport.close();
    });
  });
}
