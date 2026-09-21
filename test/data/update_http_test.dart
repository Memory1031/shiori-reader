import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/updates/update_http.dart';
import 'package:shiori/domain/contracts/app_updates.dart';
import 'package:shiori/domain/contracts/cancellation.dart';
import 'network/network_test_support.dart';

void main() {
  final uri = releaseAsset('v1.2.1', 'package.zip');
  Matcher issue(UpdateProblem problem) =>
      isA<UpdateIssue>().having((e) => e.problem, 'problem', problem);
  test(
    'GitHub CDN redirects allowed, arbitrary and insecure redirects rejected',
    () async {
      for (final destination in [
        'https://release-assets.githubusercontent.com/blob',
        'https://evil.example/blob',
        'http://github.com/blob',
      ]) {
        final adapter = TestAdapter(
          (options) => options.uri == uri
              ? ResponseBody.fromString(
                  '',
                  302,
                  headers: {
                    'location': [destination],
                  },
                )
              : ResponseBody.fromString('ok', 200),
        );
        final transport = DioUpdateHttp(
          dio: Dio()..httpClientAdapter = adapter,
        );
        final future = transport.read(
          uri,
          CancellationSource().token,
          limit: 10,
        );
        if (destination.contains('release-assets')) {
          expect((await future).bytes, 'ok'.codeUnits);
        } else {
          await expectLater(future, throwsA(issue(UpdateProblem.verification)));
          expect(adapter.requests.length, 1);
        }
        transport.close();
      }
    },
  );
  test(
    'bounds apply without Content-Length; redirects have finite limit',
    () async {
      final adapter = TestAdapter(
        (_) => ResponseBody(Stream.value(Uint8List(11)), 200),
      );
      final transport = DioUpdateHttp(dio: Dio()..httpClientAdapter = adapter);
      await expectLater(
        transport.read(uri, CancellationSource().token, limit: 10),
        throwsA(issue(UpdateProblem.verification)),
      );
      transport.close();
      final loop = TestAdapter(
        (_) => ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': [uri.toString()],
          },
        ),
      );
      final looping = DioUpdateHttp(dio: Dio()..httpClientAdapter = loop);
      await expectLater(
        looping.read(uri, CancellationSource().token, limit: 10),
        throwsA(issue(UpdateProblem.verification)),
      );
      expect(loop.requests.length, 6);
      looping.close();
    },
  );
  test(
    'rate limit exposes retry time and never retries automatically',
    () async {
      final now = DateTime.utc(2030);
      final adapter = TestAdapter(
        (_) => ResponseBody.fromString(
          '',
          429,
          headers: {
            'retry-after': ['120'],
          },
        ),
      );
      final transport = DioUpdateHttp(
        dio: Dio()..httpClientAdapter = adapter,
        now: () => now,
      );
      await expectLater(
        transport.read(uri, CancellationSource().token, limit: 10),
        throwsA(
          isA<UpdateIssue>().having(
            (e) => e.retryAt,
            'retryAt',
            now.add(const Duration(minutes: 2)),
          ),
        ),
      );
      expect(adapter.requests.length, 1);
      transport.close();
    },
  );
  test('cancellation ends streaming and closes transport on dispose', () async {
    final source = CancellationSource();
    final adapter = TestAdapter(
      (_) =>
          ResponseBody(Stream.fromIterable([Uint8List(3), Uint8List(3)]), 200),
    );
    final transport = DioUpdateHttp(dio: Dio()..httpClientAdapter = adapter);
    await expectLater(
      transport.download(
        uri,
        source.token,
        limit: 10,
        chunk: (_) async => source.cancel(),
      ),
      throwsA(issue(UpdateProblem.cancelled)),
    );
    transport.close();
    expect(adapter.closed, isTrue);
  });
}
