import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/contracts/app_updates.dart';
import '../../domain/contracts/cancellation.dart';

const updateRepositoryPath = 'Memory1031/shiori-reader';
Uri releasePage(String tag) =>
    Uri.https('github.com', '/$updateRepositoryPath/releases/tag/$tag');
Uri releaseAsset(String tag, String name) => Uri.https(
  'github.com',
  '/$updateRepositoryPath/releases/download/$tag/$name',
);

class UpdateReply {
  const UpdateReply(this.bytes, this.headers, {this.notModified = false});
  final Uint8List bytes;
  final Map<String, String> headers;
  final bool notModified;
}

abstract interface class UpdateHttp {
  Future<UpdateReply> read(
    Uri uri,
    CancellationToken token, {
    required int limit,
    String? etag,
  });
  Future<void> download(
    Uri uri,
    CancellationToken token, {
    required int limit,
    required Future<void> Function(List<int>) chunk,
  });
  void close();
}

void checkUpdateCancellation(CancellationToken token) {
  if (token.isCancelled) throw const UpdateIssue(UpdateProblem.cancelled);
}

/// Redirects are followed explicitly: credentials are never attached and each
/// hop must remain on GitHub's HTTPS release delivery hosts.
final class DioUpdateHttp implements UpdateHttp {
  DioUpdateHttp({Dio? dio, DateTime Function()? now})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ),
      _now = now ?? DateTime.now;
  final Dio _dio;
  final DateTime Function() _now;
  static bool allowed(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      {
        'api.github.com',
        'github.com',
        'release-assets.githubusercontent.com',
        'objects.githubusercontent.com',
      }.contains(uri.host);

  Future<UpdateReply> _request(
    Uri initial,
    CancellationToken token,
    int limit, {
    String? etag,
    Future<void> Function(List<int>)? chunk,
  }) async {
    final cancel = CancelToken();
    unawaited(token.whenCancelled.then((_) => cancel.cancel()));
    var uri = initial;
    try {
      for (var hop = 0; hop <= 5; hop++) {
        checkUpdateCancellation(token);
        if (!allowed(uri)) throw const UpdateIssue(UpdateProblem.verification);
        final response = await _dio.getUri<ResponseBody>(
          uri,
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (_) => true,
            headers: {
              'User-Agent': 'Shiori-Updater',
              'Accept': uri.host == 'api.github.com'
                  ? 'application/vnd.github+json'
                  : 'application/octet-stream',
              if (uri.host == 'api.github.com')
                'X-GitHub-Api-Version': '2022-11-28',
              if (etag != null && uri == initial) 'If-None-Match': etag,
            },
          ),
        );
        final body = response.data!;
        final headers = {
          for (final entry in response.headers.map.entries)
            entry.key.toLowerCase(): entry.value.join(','),
        };
        final status = response.statusCode!;
        if ({301, 302, 303, 307, 308}.contains(status)) {
          await body.stream.listen(null).cancel();
          final location = headers['location'];
          if (location == null || hop == 5) {
            throw const UpdateIssue(UpdateProblem.verification);
          }
          uri = uri.resolve(location);
          continue;
        }
        if (status == 304) {
          await body.stream.listen(null).cancel();
          if (etag == null) throw const UpdateIssue(UpdateProblem.incomplete);
          return UpdateReply(Uint8List(0), headers, notModified: true);
        }
        if (status != 200) {
          await body.stream.listen(null).cancel();
          if (status == 403 || status == 429) {
            final now = _now().toUtc();
            var retry = now.add(const Duration(minutes: 1));
            final seconds = int.tryParse(headers['retry-after'] ?? '');
            final reset = int.tryParse(headers['x-ratelimit-reset'] ?? '');
            if (seconds != null && seconds > 0) {
              retry = now.add(Duration(seconds: seconds.clamp(1, 2592000)));
            }
            if (seconds == null && headers['retry-after'] != null) {
              try {
                final date = HttpDate.parse(headers['retry-after']!);
                if (date.isAfter(retry)) retry = date;
              } on FormatException {
                /* use default */
              }
            }
            if (reset != null && reset > 0 && reset < 4102444800) {
              final date = DateTime.fromMillisecondsSinceEpoch(
                reset * 1000,
                isUtc: true,
              );
              if (date.isAfter(retry)) retry = date;
            }
            throw UpdateIssue(UpdateProblem.rateLimited, retryAt: retry);
          }
          throw UpdateIssue(
            status == 404 ? UpdateProblem.incomplete : UpdateProblem.network,
          );
        }
        final declared = int.tryParse(headers['content-length'] ?? '');
        if (declared != null && declared > limit) {
          await body.stream.listen(null).cancel();
          throw const UpdateIssue(UpdateProblem.verification);
        }
        final bytes = BytesBuilder(copy: false);
        var received = 0;
        await for (final data in body.stream) {
          checkUpdateCancellation(token);
          received += data.length;
          if (received > limit) {
            cancel.cancel();
            throw const UpdateIssue(UpdateProblem.verification);
          }
          if (chunk == null) {
            bytes.add(data);
          } else {
            await chunk(data);
          }
        }
        checkUpdateCancellation(token);
        return UpdateReply(bytes.takeBytes(), headers);
      }
      throw const UpdateIssue(UpdateProblem.verification);
    } on DioException {
      checkUpdateCancellation(token);
      throw const UpdateIssue(UpdateProblem.network);
    } on SocketException {
      checkUpdateCancellation(token);
      throw const UpdateIssue(UpdateProblem.network);
    } on TimeoutException {
      throw const UpdateIssue(UpdateProblem.network);
    }
  }

  @override
  Future<UpdateReply> read(
    Uri uri,
    CancellationToken token, {
    required int limit,
    String? etag,
  }) => _request(uri, token, limit, etag: etag);
  @override
  Future<void> download(
    Uri uri,
    CancellationToken token, {
    required int limit,
    required Future<void> Function(List<int>) chunk,
  }) async {
    await _request(uri, token, limit, chunk: chunk);
  }

  @override
  void close() => _dio.close(force: true);
}
