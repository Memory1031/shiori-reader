import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import '../../../domain/content_identity.dart';
import '../../../domain/contracts/contracts.dart';
import '../../../domain/models/models.dart';
import '../../../shared/app_logger.dart';
import '../../network/network_client.dart';
import '../../network/network_transport.dart';
import '../../network/network_types.dart';
import '../../network/request_scheduler.dart';
import 'lightnovel_api.dart';
import 'lightnovel_identity.dart';

Uri _uri(String raw) {
  final uri = Uri.parse('https://www.lightnovel.fun/').resolve(raw);
  if (raw.trim().isEmpty ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.hasFragment ||
      !{'www.lightnovel.fun', 'api.lightnovel.fun'}.contains(uri.host)) {
    throw const FormatException('Invalid media locator');
  }
  return uri;
}

class _MediaPolicy implements SourceNetworkPolicy {
  _MediaPolicy(this.uri);
  final Uri uri;
  @override
  SourceId get sourceId => lightNovelSourceId;
  @override
  bool allows(Uri target) => target == uri;
  @override
  Map<String, String> headersFor(Uri target) => const {
    'Accept': 'image/jpeg,image/png,image/webp,image/gif,image/avif',
    'Referer': 'https://www.lightnovel.fun/',
  };
  @override
  void acceptResponse(Uri uri, Map<String, List<String>> headers) {}
}

/// No locator cache: every call resolves from fresh allowed metadata.
final class LightNovelMedia implements SourceMedia {
  LightNovelMedia({
    required this.api,
    required this.scheduler,
    required this.logger,
    this.adapterFactory,
  });
  final LightNovelApi api;
  final RequestScheduler scheduler;
  final AppLogger logger;
  final HttpClientAdapter Function()? adapterFactory;
  final _lifetime = CancellationSource();
  final _active = <NetworkTransport>{};
  Failure<SourceMediaBody> fail(
    FailureKind kind, {
    FailureContext context = FailureContext.none,
  }) => Failure(
    AppFailure(kind: kind, operation: Operation.media, context: context),
  );
  @override
  Future<Result<SourceMediaBody>> openMedia(
    MediaRef ref, {
    required int maxBytes,
    required CancellationToken cancellation,
  }) async {
    if (maxBytes < 1 || maxBytes > 20 * 1024 * 1024) {
      throw ArgumentError('Invalid media budget');
    }
    final linked = CancellationSource();
    if (cancellation.isCancelled || _lifetime.token.isCancelled) {
      linked.cancel();
    }
    final a = cancellation.whenCancelled.asStream().listen(
      (_) => linked.cancel(),
    );
    final b = _lifetime.token.whenCancelled.asStream().listen(
      (_) => linked.cancel(),
    );
    final token = linked.token;
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    NetworkTransport? transport;
    try {
      if (token.isCancelled) return fail(FailureKind.cancelled);
      if (ref.sourceId != lightNovelSourceId) {
        return fail(FailureKind.parse, context: FailureContext.invalidContent);
      }
      final cover = RegExp(r'^cover:v1:([1-9][0-9]*)$').firstMatch(ref.mediaId);
      final image = RegExp(
        r'^image:v1:([1-9][0-9]*):([1-9][0-9]*):([a-f0-9]{64})$',
      ).firstMatch(ref.mediaId);
      if (cover == null && image == null) {
        return fail(FailureKind.parse, context: FailureContext.invalidContent);
      }
      final book = (cover ?? image)!.group(1)!;
      final response = await api.request(
        cover != null ? LightNovelEndpoint.detail : LightNovelEndpoint.chapter,
        cover != null
            ? {'book_id': book, 'with_volumes': 0}
            : {'book_id': book, 'chapter_id': image!.group(2)!},
        cancellation: token,
        deadline: deadline,
      );
      if (response case Failure(:final failure)) {
        return Failure(
          AppFailure(
            kind: failure.kind,
            operation: Operation.media,
            retryPolicy: failure.retryPolicy,
            context: failure.context,
            diagnosticId: failure.diagnosticId,
            retryNotBefore: failure.retryNotBefore,
          ),
        );
      }
      final data = (response as Success<Map<String, dynamic>>).value;
      if (lightNovelRemoteId(data['book_id']) != book) {
        return fail(FailureKind.parse, context: FailureContext.invalidContent);
      }
      Uri? target;
      if (cover != null) {
        final raw = data['cover_url'];
        if (raw is! String || raw.isEmpty) return fail(FailureKind.notFound);
        target = _uri(raw);
      } else {
        if (lightNovelRemoteId(data['chapter_id']) != image!.group(2)) {
          return fail(
            FailureKind.parse,
            context: FailureContext.invalidContent,
          );
        }
        if (data['locked'] == 1) return fail(FailureKind.accessRestricted);
        if (data['locked'] is! int || data['locked'] != 0) {
          return fail(
            FailureKind.parse,
            context: FailureContext.invalidContent,
          );
        }
        final snapshot = data['body_snapshot'];
        if (snapshot is! Map || snapshot['body_html'] is! String) {
          return fail(
            FailureKind.parse,
            context: FailureContext.invalidContent,
          );
        }
        final root = html.parseFragment(snapshot['body_html'] as String);
        if (root.querySelector('form,input[type=password]') != null) {
          return fail(FailureKind.accessRestricted);
        }
        for (final img in root.querySelectorAll('img')) {
          final raw = img.attributes['data-src']?.trim().isNotEmpty == true
              ? img.attributes['data-src']
              : img.attributes['data-original']?.trim().isNotEmpty == true
              ? img.attributes['data-original']
              : img.attributes['src'];
          if (raw == null) continue;
          final uri = _uri(raw);
          if (ContentIdentity.digest('lightnovel-image-locator', [
                uri.origin,
                uri.path,
              ]) ==
              image.group(3)) {
            if (target != null && target != uri) {
              return fail(
                FailureKind.parse,
                context: FailureContext.invalidContent,
              );
            }
            target = uri;
          }
        }
      }
      if (target == null) return fail(FailureKind.notFound);
      if (token.isCancelled) return fail(FailureKind.cancelled);
      transport = NetworkTransport(
        policy: _MediaPolicy(target),
        logger: logger,
        adapter: adapterFactory?.call(),
      );
      _active.add(transport);
      final result =
          await NetworkClient(transport: transport, scheduler: scheduler).send(
            NetworkRequest(
              uri: target,
              operation: Operation.media,
              maxBytes: maxBytes,
              mimeTypes: const {
                'image/jpeg',
                'image/png',
                'image/webp',
                'image/gif',
                'image/avif',
              },
              safeToRepeat: false,
              maxRedirects: 0,
              receiveTimeout: const Duration(seconds: 30),
            ),
            cancellation: token,
            deadline: deadline,
          );
      if (result case Failure(:final failure)) return Failure(failure);
      if (token.isCancelled) return fail(FailureKind.cancelled);
      final responseBytes = (result as Success<NetworkResponse>).value;
      if (responseBytes.bytes.isEmpty) {
        return fail(FailureKind.parse, context: FailureContext.invalidContent);
      }
      final format = switch (responseBytes
          .header('content-type')
          ?.split(';')
          .first
          .trim()
          .toLowerCase()) {
        'image/jpeg' => MediaFormat.jpeg,
        'image/png' => MediaFormat.png,
        'image/webp' => MediaFormat.webp,
        'image/gif' => MediaFormat.gif,
        'image/avif' => MediaFormat.avif,
        _ => MediaFormat.unknown,
      };
      return Success(
        _Body(
          responseBytes.bytes,
          MediaInfo(format: format, byteLength: responseBytes.bytes.length),
          maxBytes,
          cancellation,
        ),
      );
    } on FormatException {
      return fail(FailureKind.parse, context: FailureContext.invalidContent);
    } on ArgumentError {
      return fail(FailureKind.parse, context: FailureContext.invalidContent);
    } catch (_) {
      return fail(
        token.isCancelled ? FailureKind.cancelled : FailureKind.network,
      );
    } finally {
      if (transport != null) {
        _active.remove(transport);
        _closeTransport(transport);
      }
      await a.cancel();
      await b.cancel();
    }
  }

  void close() {
    _lifetime.cancel();
    for (final transport in _active.toList()) {
      _closeTransport(transport);
    }
  }

  void _closeTransport(NetworkTransport transport) {
    try {
      transport.close();
    } catch (_) {
      logger.local(
        AppFailure(kind: FailureKind.network, operation: Operation.media),
      );
    }
  }
}

class _Body implements SourceMediaBody {
  _Body(this._bytes, this.info, this.maxBytes, this.token);
  Uint8List? _bytes;
  final CancellationToken token;
  @override
  final MediaInfo info;
  @override
  final int maxBytes;
  bool _listened = false;
  @override
  Stream<Result<List<int>>> get chunks {
    if (_listened) throw StateError('Single consumer body');
    _listened = true;
    return _read();
  }

  Stream<Result<List<int>>> _read() async* {
    try {
      var offset = 0;
      while (_bytes != null && offset < _bytes!.length) {
        if (token.isCancelled) {
          yield Failure(AppFailure.cancelled(Operation.media));
          return;
        }
        final end = (offset + 65536).clamp(0, _bytes!.length);
        yield Success(List<int>.unmodifiable(_bytes!.sublist(offset, end)));
        offset = end;
      }
    } finally {
      await close();
    }
  }

  @override
  Future<void> close() async {
    _bytes = null;
  }
}
