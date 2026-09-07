import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/data/network/network_client.dart';
import 'package:shiori/data/network/network_transport.dart';
import 'package:shiori/data/network/network_types.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';

import '../data/network/network_test_support.dart';

void check(bool value) {
  if (!value) throw StateError('Probe check failed');
}

/// Test-only bridge: a production Source will resolve its own media IDs/URLs.
class ProbeMediaSource implements SourceMedia {
  ProbeMediaSource(this.client);
  final NetworkClient client;
  @override
  Future<Result<SourceMediaBody>> openMedia(
    MediaRef ref, {
    required int maxBytes,
    required CancellationToken cancellation,
  }) async {
    final result = await client.send(
      NetworkRequest(
        uri: Uri.parse('https://example.test/image'),
        operation: Operation.media,
        safeToRepeat: true,
        maxBytes: maxBytes,
        mimeTypes: {'image/png'},
        receiveTimeout: const Duration(seconds: 30),
      ),
      cancellation: cancellation,
    );
    return result.map((response) => _Body(response.bytes, maxBytes));
  }
}

class _Body implements SourceMediaBody {
  _Body(this.bytes, this.maxBytes);
  final Uint8List bytes;
  @override
  final int maxBytes;
  bool closed = false;
  @override
  MediaInfo get info =>
      MediaInfo(format: MediaFormat.png, byteLength: bytes.length);
  @override
  Stream<Result<List<int>>> get chunks async* {
    if (!closed) yield Success(List<int>.unmodifiable(bytes));
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

Future<Uint8List> verifyNetworkMedia() async {
  final bytes = fixturePng(64, 64, 7);
  var calls = 0;
  final adapter = TestAdapter((_) {
    calls++;
    return calls == 1
        ? response(status: 503)
        : response(
            bytes: bytes,
            headers: {
              'content-type': ['image/png'],
            },
          );
  });
  final logger = AppLogger();
  final transport = NetworkTransport(
    policy: TestPolicy(),
    logger: logger,
    adapter: adapter,
  );
  final scheduler = RequestScheduler();
  final client = NetworkClient(
    transport: transport,
    scheduler: scheduler,
    random: (_) => 0,
  );
  final repository = MemoryImageRepository(
    resolve: (_) => ProbeMediaSource(client),
  );
  final ref = MediaRef(sourceId: SourceId('test'), mediaId: 'sample');
  final cancel = CancellationSource();
  try {
    check(
      !(await repository.load(
        ref,
        mode: ReadMode.cacheOnly,
        cancellation: cancel.token,
      )).isSuccess,
    );
    check(calls == 0);
    final first = repository.load(
      ref,
      mode: ReadMode.cacheFirst,
      cancellation: cancel.token,
    );
    final second = repository.load(
      ref,
      mode: ReadMode.cacheFirst,
      cancellation: cancel.token,
    );
    final a = (await first as Success<LoadResult<MediaLease>>).value.value;
    final b = (await second as Success<LoadResult<MediaLease>>).value.value;
    check(calls == 2 && !identical(a, b) && identical(a.data, b.data));
    final imageBytes = (a.data as MemoryMedia).bytes;
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    check(frame.image.width == 64 && frame.image.height == 64);
    frame.image.dispose();
    codec.dispose();
    await a.close();
    check(repository.retainedBytes > 0);
    await b.close();
    check(repository.retainedBytes == 0);
    check(scheduler.activeCount == 0 && repository.pendingCount == 0);
    return imageBytes;
  } finally {
    cancel.cancel();
    repository.close();
    scheduler.close();
    transport.close();
  }
}

void main() => runApp(const MaterialApp(home: _Probe()));

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  Uint8List? _bytes;
  String _status = 'NETWORK_MEDIA_RUNNING';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final bytes = await verifyNetworkMedia();
        if (mounted) {
          setState(() {
            _bytes = bytes;
            _status = 'NETWORK_MEDIA_PASS';
          });
        }
        debugPrint(
          'NETWORK_MEDIA_PASS attempts=2 sharedLeases=2 retainedBytes=0 codec=64x64',
        );
      } catch (_) {
        if (mounted) setState(() => _status = 'NETWORK_MEDIA_FAIL');
        debugPrint('NETWORK_MEDIA_FAIL');
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status),
            if (_bytes != null) Image.memory(_bytes!, width: 128, height: 128),
          ],
        ),
      ),
    ),
  );
}
