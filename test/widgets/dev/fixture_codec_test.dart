import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import '../../support/fixture_codec_check.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all 20 fixture PNGs decode to expected dimensions and pixels',
    () async {
      expect(await decodeFixtureImages(), 20);
      final env = FixtureEnvironment(
        scenario: FixtureScenario.unknownImageSize,
      );
      try {
        final result = await env.images.load(
          fixtureMediaRef(0),
          mode: ReadMode.refresh,
          cancellation: CancellationSource().token,
        );
        final lease = (result as Success<LoadResult<MediaLease>>).value.value;
        try {
          final data = lease.data as MemoryMedia;
          expect(data.info.width, isNull);
          expect(data.info.height, isNull);
          final codec = await ui.instantiateImageCodec(data.bytes);
          try {
            final frame = await codec.getNextFrame();
            try {
              expect(frame.image.width, env.source.data.dimensions(0).$1);
              expect(frame.image.height, env.source.data.dimensions(0).$2);
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        } finally {
          await lease.close();
        }
      } finally {
        await env.close();
      }
    },
  );
}
