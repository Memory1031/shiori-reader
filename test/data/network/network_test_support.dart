import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shiori/data/network/network_types.dart';
import 'package:shiori/data/network/network_transport.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';

class TestPolicy implements SourceNetworkPolicy {
  TestPolicy({
    this.label = 'test',
    this.headers = const {},
    this.hosts = const {'example.test', 'media.test'},
  });
  final String label;
  final Map<String, String> headers;
  final Set<String> hosts;
  int accepted = 0;
  @override
  SourceId get sourceId => SourceId(label);
  @override
  bool allows(Uri uri) => hosts.contains(uri.host);
  @override
  Map<String, String> headersFor(Uri uri) => headers;
  @override
  void acceptResponse(Uri uri, Map<String, List<String>> headers) {
    accepted++;
  }
}

class TestAdapter implements HttpClientAdapter {
  TestAdapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  int cancellations = 0;
  bool closed = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    cancelFuture?.then((_) {
      cancellations++;
    });
    return await respond(options);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

/// The scheduler clock tests isolate retry timing from Dio's interceptor futures.
/// Transport bytes/cancellation and actual Dio redirects have separate tests.
class ClockTransport extends NetworkTransport {
  ClockTransport({
    required TestAdapter adapter,
    required DateTime Function() now,
  }) : clockAdapter = adapter,
       super(
         policy: TestPolicy(),
         logger: AppLogger(),
         adapter: adapter,
         now: now,
       );
  final TestAdapter clockAdapter;
  @override
  Future<Result<NetworkResponse>> attempt(
    NetworkRequest request, {
    required CancellationToken cancellation,
    required DateTime deadline,
    int attemptNumber = 1,
    bool crossOrigin = false,
  }) async {
    final body = await clockAdapter.fetch(
      RequestOptions(path: request.uri.toString()),
      null,
      null,
    );
    unawaited(body.stream.listen(null).cancel());
    return Success(
      NetworkResponse(
        status: body.statusCode,
        headers: body.headers,
        bytes: Uint8List(0),
      ),
    );
  }
}

ResponseBody response({
  int status = 200,
  List<int> bytes = const [1, 2],
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromBytes(
  bytes,
  status,
  headers: {
    'content-type': ['application/json'],
    ...headers,
  },
);
