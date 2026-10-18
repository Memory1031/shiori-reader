import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/features/reader/reader_image.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/shared/paper_diagram.dart';
import 'package:shiori/shared/source_image.dart';
import 'image_sizing_test.dart' show Images;
import 'source_image_test.dart' show app, frames;
import 'paper_diagram_test.dart' show drawing, png;

/// Original fixture: two solid rounded marks, not commercial book artwork.
Future<ui.Image> ornament({String kind = 'plain'}) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder)
    ..drawColor(
      kind == 'transparent' ? Colors.transparent : Colors.white,
      BlendMode.src,
    );
  final ink = Paint()
    ..color = kind == 'gray' ? const Color(0xff404040) : Colors.black;
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(5, 5, 10, 10),
      const Radius.circular(2),
    ),
    ink,
  );
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(19, 19, 8, 8),
      const Radius.circular(2),
    ),
    ink,
  );
  if (kind == 'enclosed') {
    c.drawColor(Colors.white, BlendMode.src);
    c.drawRect(
      const Rect.fromLTWH(8, 8, 16, 16),
      Paint()..color = Colors.black,
    );
    c.drawRect(
      const Rect.fromLTWH(14, 14, 4, 4),
      Paint()..color = Colors.white,
    );
  }
  if (kind == 'edge') {
    c.drawRect(const Rect.fromLTWH(0, 0, 2, 32), ink);
  }
  if (kind == 'bars' || kind == 'horizontal-bars') {
    c.drawColor(Colors.white, BlendMode.src);
    if (kind == 'horizontal-bars') {
      c.translate(32, 0);
      c.rotate(1.5707963267948966);
    }
    c.drawRect(const Rect.fromLTWH(5, 5, 8, 22), ink);
    c.drawRect(const Rect.fromLTWH(21, 5, 2, 22), ink);
  }
  if (kind == 'color') {
    c.drawRect(const Rect.fromLTWH(18, 5, 4, 4), Paint()..color = Colors.red);
  }
  if (kind == 'matrix-marker') {
    c.drawColor(Colors.white, BlendMode.src);
    // Original information-marker fixture with a white locator interior.
    c.drawRect(const Rect.fromLTWH(3, 3, 9, 9), ink);
    c.drawRect(const Rect.fromLTWH(5, 5, 5, 5), Paint()..color = Colors.white);
    c.drawRect(const Rect.fromLTWH(19, 19, 10, 10), ink);
  }
  if (kind == 'photo') {
    c.drawRect(
      const Rect.fromLTWH(6, 6, 20, 20),
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.black, Colors.white],
        ).createShader(const Rect.fromLTWH(6, 6, 20, 20)),
    );
  }
  final p = recorder.endRecording();
  try {
    return await p.toImage(32, 32);
  } finally {
    p.dispose();
  }
}

final localMark = MediaRef(
  sourceId: LocalBookIdentity.sourceId,
  mediaId: 'original-ornament',
);

void main() {
  testWidgets('compact bar patterns retain their original polarity', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final kind in ['bars', 'horizontal-bars', 'matrix-marker']) {
        final image = await ornament(kind: kind);
        try {
          final original = await png(image);
          for (final mode in PaperImageMode.values) {
            final mask = await paperDiagramMask(
              image,
              mode: mode,
              intrinsicSize: const Size(32, 32),
            );
            try {
              expect(mask, isNull, reason: '$kind / $mode');
            } finally {
              mask?.dispose();
            }
          }
          expect(await png(image), original);
        } finally {
          image.dispose();
        }
      }
    });
  });
  testWidgets('late mode A-B-A decodes cannot replace the current original', (
    tester,
  ) async {
    late Uint8List bytes;
    await tester.runAsync(() async {
      final image = await ornament();
      bytes = await png(image);
      image.dispose();
    });
    final images = Images(bytes);
    final pending = <Completer<DecodedSourceImage>>[];
    final made = <ui.Image>[];
    var sizes = 0;
    Future<DecodedSourceImage> decode(_, int width) {
      final gate = Completer<DecodedSourceImage>();
      pending.add(gate);
      return gate.future;
    }

    Future<void> show(PaperImageMode mode) async {
      await tester.pumpWidget(
        app(
          Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: SourceImage(
                media: localMark,
                repository: images,
                decoder: decode,
                paperInk: Colors.black,
                paperMode: mode,
                onIntrinsicSize: (_) => sizes++,
              ),
            ),
          ),
        ),
      );
      await frames(tester);
    }

    await show(PaperImageMode.diagram);
    await show(PaperImageMode.ornament);
    await show(PaperImageMode.diagram);
    expect(pending.length, 3);
    Future<void> finish(int i) async {
      final image = (await tester.runAsync(() => ornament()))!;
      made.add(image);
      pending[i].complete(DecodedSourceImage(image, const Size(32, 32)));
      await frames(tester);
    }

    await finish(2);
    final current = tester.widget<RawImage>(find.byType(RawImage)).image;
    await finish(1);
    await finish(0);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(current));
    expect(tester.widget<RawImage>(find.byType(RawImage)).color, isNull);
    expect(sizes, 1);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    expect(images.closed, images.loads);
    expect(made.every((image) => image.debugDisposed), isTrue);
  });
  testWidgets(
    'compact opaque marks use an opt-in mask, diagrams keep their rules',
    (tester) async {
      await tester.runAsync(() async {
        final image = await ornament();
        final before = await png(image);
        expect(await paperDiagramMask(image), isNull);
        expect(
          await paperDiagramMask(image, mode: PaperImageMode.ornament),
          isNull,
        );
        expect(
          await paperDiagramMask(
            image,
            mode: PaperImageMode.ornament,
            intrinsicSize: const Size(1024, 1024),
          ),
          isNull,
        );
        final mask = await paperDiagramMask(
          image,
          mode: PaperImageMode.ornament,
          intrinsicSize: const Size(32, 32),
        );
        expect(mask, isNotNull);
        final pixels = (await mask!.toByteData())!.buffer.asUint8List();
        expect(pixels.sublist(0, 4), [0, 0, 0, 0]);
        expect(pixels.where((v) => v > 0 && v < 255), isNotEmpty);
        for (final paper in [
          Colors.white,
          const Color(0xfff3ead5),
          const Color(0xff161819),
        ]) {
          final rec = ui.PictureRecorder();
          final canvas = Canvas(rec)..drawColor(paper, BlendMode.src);
          canvas.drawImage(
            mask,
            Offset.zero,
            Paint()
              ..colorFilter = ColorFilter.mode(
                paper == const Color(0xff161819) ? Colors.white : Colors.black,
                BlendMode.srcIn,
              ),
          );
          final picture = rec.endRecording();
          final output = await picture.toImage(32, 32);
          final rgba = (await output.toByteData())!.buffer.asUint8List();
          expect(rgba.sublist(0, 4), [
            (paper.toARGB32() >> 16) & 255,
            (paper.toARGB32() >> 8) & 255,
            paper.toARGB32() & 255,
            255,
          ]);
          expect(
            rgba[(8 * 32 + 8) * 4],
            paper == const Color(0xff161819) ? 255 : 0,
          );
          output.dispose();
          picture.dispose();
        }
        expect(await png(image), before);
        mask.dispose();
        image.dispose();
        final lines = await drawing(256, 256);
        final fine = await paperDiagramMask(lines);
        expect(fine, isNotNull);
        final body = await paperDiagramMask(
          lines,
          mode: PaperImageMode.body,
          intrinsicSize: const Size(1024, 1024),
        );
        expect(body, isNotNull);
        body?.dispose();
        expect(
          await paperDiagramMask(
            lines,
            mode: PaperImageMode.ornament,
            intrinsicSize: const Size(1024, 1024),
          ),
          isNull,
        );
        fine?.dispose();
        lines.dispose();
      });
    },
  );
  testWidgets(
    'compact mode rejects meaningful white areas, tone, color and alpha',
    (tester) async {
      await tester.runAsync(() async {
        for (final kind in [
          'enclosed',
          'photo',
          'color',
          'gray',
          'edge',
          'transparent',
        ]) {
          final image = await ornament(kind: kind);
          final before = await png(image);
          expect(
            await paperDiagramMask(
              image,
              mode: PaperImageMode.ornament,
              intrinsicSize: const Size(32, 32),
            ),
            isNull,
            reason: kind,
          );
          expect(await png(image), before);
          image.dispose();
        }
      });
    },
  );
  testWidgets(
    'mode changes separate cached masks from originals and theme changes reuse them',
    (tester) async {
      late Uint8List bytes;
      await tester.runAsync(() async {
        final image = await ornament();
        bytes = await png(image);
        image.dispose();
      });
      final images = Images(bytes);
      Future<void> show(PaperImageMode mode, Color? ink) async {
        await tester.pumpWidget(
          app(
            SourceImageDecodeScope(
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: SourceImage(
                    media: localMark,
                    repository: images,
                    paperInk: ink,
                    paperMode: mode,
                  ),
                ),
              ),
            ),
          ),
        );
        await frames(tester);
      }

      await show(PaperImageMode.diagram, Colors.black);
      expect(tester.widget<RawImage>(find.byType(RawImage)).color, isNull);
      await show(PaperImageMode.ornament, Colors.black);
      final masked = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).color,
        Colors.black,
      );
      final loads = images.loads;
      for (final ink in [Colors.white, Colors.black]) {
        await show(PaperImageMode.ornament, ink);
        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect(raw.image, same(masked));
        expect(raw.color, ink);
      }
      expect(images.loads, loads);
      await show(PaperImageMode.ornament, null);
      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.color, isNull);
      await tester.runAsync(() async {
        expect(
          (await raw.image!.toByteData())!.buffer.asUint8List().sublist(0, 4),
          [255, 255, 255, 255],
        );
      });
      await show(PaperImageMode.ornament, Colors.white);
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).color,
        Colors.white,
      );
      await show(PaperImageMode.diagram, Colors.black);
      expect(tester.widget<RawImage>(find.byType(RawImage)).color, isNull);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(images.closed, images.loads);
    },
  );
  testWidgets(
    'page images stay original while local compact inline marks opt in',
    (tester) async {
      late Uint8List bytes;
      await tester.runAsync(() async {
        final image = await ornament();
        bytes = await png(image);
        image.dispose();
      });
      final images = Images(bytes);
      await tester.pumpWidget(
        app(
          Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: ReaderImage(
                block: ImageBlock(
                  media: localMark,
                  width: 32,
                  height: 32,
                  sizing: ImageSizing(role: ImageRole.page),
                ),
                geometry: const ReaderImageGeometry(
                  Size(32, 32),
                  0,
                  Alignment.center,
                  BoxFit.contain,
                ),
                repository: images,
                captionHeight: 0,
                onIntrinsicSize: (_) {},
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      expect(tester.widget<RawImage>(find.byType(RawImage)).color, isNull);
      Future<void> inline({int? background}) async {
        await tester.pumpWidget(
          app(
            Center(
              child: SizedBox(
                width: 300,
                child: ReaderLinkedText(
                  text: '\uFFFC',
                  prefix: '',
                  blockOffset: 0,
                  links: const [],
                  style: const TextStyle(fontSize: 20),
                  align: TextAlign.center,
                  scaler: TextScaler.noScaling,
                  authoredBackground: background,
                  images: images,
                  inlineImages: [
                    InlineImage(
                      offset: 0,
                      media: localMark,
                      widthEm: 2,
                      heightEm: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await frames(tester);
      }

      await inline();
      expect(tester.widget<RawImage>(find.byType(RawImage)).color, isNotNull);
      await inline(background: 0xff225588);
      expect(tester.widget<RawImage>(find.byType(RawImage)).color, isNull);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(images.closed, images.loads);
    },
  );
}
