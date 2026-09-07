import 'dart:ui' as ui;

import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';

/// Shared host/Android codec check; no widget or production app entry changes.
Future<int> decodeFixtureImages() async {
  var decoded = 0;
  final env = FixtureEnvironment();
  try {
    for (var i = 0; i < 20; i++) {
      final result = await env.images.load(
        fixtureMediaRef(i),
        mode: ReadMode.refresh,
        cancellation: CancellationSource().token,
      );
      final lease = (result as Success<LoadResult<MediaLease>>).value.value;
      try {
        final data = lease.data as MemoryMedia;
        final codec = await ui.instantiateImageCodec(data.bytes);
        try {
          final frame = await codec.getNextFrame();
          try {
            final expected = env.source.data.dimensions(i);
            if (frame.image.width != expected.$1 ||
                frame.image.height != expected.$2) {
              throw StateError('Fixture image size mismatch: $i');
            }
            final pixels = await frame.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (pixels == null ||
                pixels.lengthInBytes != expected.$1 * expected.$2 * 4) {
              throw StateError('Fixture pixels missing: $i');
            }
            final first = (env.source.data.seed + i) % 2 == 0 ? 240 : 70;
            if (pixels.getUint8(0) != first || pixels.getUint8(3) != 255) {
              throw StateError('Fixture pixel mismatch: $i');
            }
            decoded++;
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        await lease.close();
      }
    }
    return decoded;
  } finally {
    await env.close();
  }
}
