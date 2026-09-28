import 'dart:async';
import 'dart:io';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_image_preview.dart';
import 'package:shiori/data/media/export/image_export_operation.dart';
import '../../data/media/image_export_test.dart'
    show ExportRepository, ExportDestination;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/shared/paper_diagram.dart';
import 'package:shiori/shared/source_image.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'source_image_test.dart' show app, frames;

Future<ui.Image> drawing(
  int width,
  int height, {
  String kind = 'diagram',
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(
    kind == 'transparent' ? Colors.transparent : Colors.white,
    BlendMode.src,
  );
  final paint = Paint()..color = const Color(0xff101010);
  for (var y = 10; y < height - 10; y += 18) {
    for (var x = 10; x < width - 10; x += 13) {
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 5, 1.4), paint);
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.4, 6), paint);
    }
  }
  if (kind == 'solid') {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width * .15, height.toDouble()),
      Paint()..color = Colors.black,
    );
  }
  if (kind == 'color') {
    canvas.drawRect(
      Rect.fromLTWH(10, 10, width * .4, height * .4),
      Paint()..color = Colors.red,
    );
  }
  if (kind == 'photo') {
    for (var y = 0; y < height; y++) {
      final g = 40 + y * 190 ~/ height;
      canvas.drawRect(
        Rect.fromLTWH(0, y.toDouble(), width.toDouble(), 1),
        Paint()..color = Color.fromARGB(255, g, g, g),
      );
    }
  }
  if (kind == 'ambiguous') {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width * .1, height.toDouble()),
      Paint()..color = Colors.grey,
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> png(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  return Uint8List.fromList(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

void main() {
  testWidgets(
    'pending image A to B to A, width and dispose reject stale masks',
    (tester) async {
      final env = FixtureEnvironment();
      final repo = MemoryImageRepository(resolve: (_) => env.source);
      final pending = <Completer<DecodedSourceImage>>[];
      final made = <ui.Image>[];
      var sizes = 0;
      Future<DecodedSourceImage> decoder(MediaData data, int width) {
        final gate = Completer<DecodedSourceImage>();
        pending.add(gate);
        return gate.future;
      }

      Future<void> show(int id, double width, Color ink) async {
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: width,
                height: 200,
                child: SourceImage(
                  media: fixtureMediaRef(id),
                  repository: repo,
                  decoder: decoder,
                  paperInk: ink,
                  onIntrinsicSize: (_) => sizes++,
                ),
              ),
            ),
          ),
        );
        await frames(tester);
      }

      await show(0, 200, Colors.black);
      await show(1, 200, Colors.white);
      await show(0, 240, Colors.white);
      expect(pending.length, 3);
      Future<void> complete(int i) async {
        await tester.runAsync(() async {
          final image = await drawing(256, 256);
          made.add(image);
          pending[i].complete(DecodedSourceImage(image, const Size(256, 256)));
        });
        await frames(tester);
      }

      await complete(2);
      final current = tester.widget<RawImage>(find.byType(RawImage)).image;
      await complete(0);
      await complete(1);
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        same(current),
      );
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).color,
        Colors.white,
      );
      expect(sizes, 1);
      await show(1, 200, Colors.black);
      await tester.pumpWidget(const SizedBox());
      await complete(3);
      expect(made.every((image) => image.debugDisposed), isTrue);
      expect(current!.debugDisposed, isTrue);
      expect(repo.retainedBytes, 0);
      expect(repo.pendingCount, 0);
      expect(tester.takeException(), isNull);
      repo.close();
      await env.close();
    },
  );
  testWidgets(
    'native mask cache never contaminates original preview or exported bytes',
    (tester) async {
      late Uint8List bytes;
      await tester.runAsync(() async {
        final image = await drawing(512, 512);
        bytes = await png(image);
        image.dispose();
      });
      final repo = ExportRepository(
        MemoryMedia(
          bytes: bytes,
          info: MediaInfo(format: MediaFormat.png),
        ),
      );
      late Directory temp;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('diagram-export-');
      });
      final destination = ExportDestination();
      final exporter = ImageExportOperation(
        stagingRoot: () async => temp,
        destination: destination,
      );
      final block = ImageBlock(
        media: MediaRef(sourceId: SourceId('local'), mediaId: 'diagram'),
        width: 512,
        height: 512,
      );
      await tester.pumpWidget(
        app(
          SourceImageDecodeScope(
            child: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 256,
                  height: 256,
                  child: ReaderImage(
                    block: block,
                    repository: repo,
                    captionHeight: 0,
                    onIntrinsicSize: (_) {},
                    onTap: () => showReaderImagePreview(
                      context,
                      block: block,
                      repository: repo,
                      exporter: exporter,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      expect(tester.widget<RawImage>(find.byType(RawImage)).color, isNotNull);
      await tester.tap(find.byType(ReaderImage));
      await frames(tester);
      final raw = tester.widget<RawImage>(
        find.descendant(
          of: find.byType(ReaderImagePreview),
          matching: find.byType(RawImage),
        ),
      );
      expect(raw.color, isNull);
      await tester.runAsync(() async {
        final pixels = (await raw.image!.toByteData())!.buffer.asUint8List();
        expect(pixels.sublist(0, 4), [255, 255, 255, 255]);
      });
      await tester.tap(find.byIcon(Icons.save_alt));
      await frames(tester);
      expect(destination.bytes, bytes);
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump();
      expect(
        ModalRoute.of(
          tester.element(find.byType(ReaderImagePreview)),
        )!.isCurrent,
        isFalse,
      );
      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(repo.leases.every((l) => l.closes == 1), isTrue);
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets(
    'bounded real codec accepts dense 2048 diagram and preserves antialias pixels',
    (tester) async {
      await tester.runAsync(() async {
        for (final size in [(2048, 2048), (768, 1024), (1024, 320)]) {
          final original = await drawing(size.$1, size.$2);
          final bytes = await png(original);
          final before = Uint8List.fromList(bytes);
          final decoded = await decodeSourceImage(
            MemoryMedia(
              bytes: bytes,
              info: MediaInfo(format: MediaFormat.png),
            ),
            640,
          );
          expect(
            decoded.intrinsicSize,
            Size(size.$1.toDouble(), size.$2.toDouble()),
          );
          expect(
            decoded.image.width * decoded.image.height,
            lessThanOrEqualTo(4000000),
          );
          final mask = await paperDiagramMask(decoded.image);
          expect(mask, isNotNull);
          final rgba = (await mask!.toByteData())!.buffer.asUint8List();
          expect(rgba.where((v) => v > 0 && v < 255), isNotEmpty);
          for (final paper in [
            Colors.white,
            const Color(0xfff3ead5),
            const Color(0xff161819),
          ]) {
            final ink = paper == const Color(0xff161819)
                ? Colors.white
                : Colors.black;
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)..drawColor(paper, BlendMode.src);
            canvas.drawImage(
              mask,
              Offset.zero,
              Paint()..colorFilter = ColorFilter.mode(ink, BlendMode.srcIn),
            );
            final pic = recorder.endRecording();
            final output = await pic.toImage(mask.width, mask.height);
            final pixels = (await output.toByteData())!.buffer.asUint8List();
            expect(pixels.sublist(0, 4), [
              (paper.toARGB32() >> 16) & 255,
              (paper.toARGB32() >> 8) & 255,
              paper.toARGB32() & 255,
              255,
            ]);
            final at = rgba.indexWhere((v) => v > 80) ~/ 4 * 4;
            expect(pixels[at], isNot(pixels[0]));
            output.dispose();
            pic.dispose();
          }
          expect(bytes, before);
          mask.dispose();
          decoded.image.dispose();
          original.dispose();
        }
      });
    },
  );
  for (final kind in ['color', 'photo', 'ambiguous', 'transparent', 'solid']) {
    testWidgets('uncertain $kind preserves original', (tester) async {
      await tester.runAsync(() async {
        final image = await drawing(256, 256, kind: kind);
        expect(await paperDiagramMask(image), isNull);
        image.dispose();
      });
    });
  }
  testWidgets(
    'paper changes reuse mask, lease and intrinsic size; default stays original',
    (tester) async {
      final env = FixtureEnvironment();
      final repo = MemoryImageRepository(resolve: (_) => env.source);
      var decodes = 0, sizes = 0;
      Future<DecodedSourceImage> decoder(MediaData data, int width) async {
        decodes++;
        return DecodedSourceImage(
          await drawing(256, 256),
          const Size(2048, 2048),
        );
      }

      Future<void> show(Color? ink) async {
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 256,
                height: 256,
                child: SourceImage(
                  media: fixtureMediaRef(0),
                  repository: repo,
                  decoder: decoder,
                  paperInk: ink,
                  onIntrinsicSize: (_) => sizes++,
                ),
              ),
            ),
          ),
        );
        await frames(tester);
      }

      await show(Colors.black);
      final image = tester.widget<RawImage>(find.byType(RawImage)).image;
      for (final ink in [Colors.white, Colors.black, Colors.white]) {
        await show(ink);
        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect(raw.image, same(image));
        expect(raw.color, ink);
      }
      expect(decodes, 1);
      expect(sizes, 1);
      expect(env.source.controls.calls[Operation.media], 1);
      await show(null);
      expect(tester.widget<RawImage>(find.byType(RawImage)).color, isNull);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(repo.retainedBytes, 0);
      repo.close();
      await env.close();
    },
  );
}
