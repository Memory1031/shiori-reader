import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_embedded_fonts.dart';
import 'package:shiori/features/reader/reader_inline_images.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/viewport/reader_box.dart';
import 'package:shiori/shared/source_image.dart';
import '../../data/local/support/synthetic_font.dart';

class _Lease implements MediaLease {
  _Lease(this.data);
  @override
  final MediaData data;
  @override
  bool isClosed = false;
  @override
  MediaPersistence get persistence => MediaPersistence.memoryOnly;
  @override
  AppFailure? get persistenceFailure => null;
  @override
  Future<void> close() async => isClosed = true;
}

class _Media implements ImageRepository {
  _Media(this.bytes);
  final Uint8List bytes;
  final leases = <_Lease>[];
  Completer<void>? pending;
  bool missing = false;
  final modes = <ReadMode>[];
  int calls = 0;
  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    calls++;
    modes.add(mode);
    await pending?.future;
    if (missing) {
      return Failure(
        AppFailure(kind: FailureKind.notFound, operation: Operation.media),
      );
    }
    final lease = _Lease(
      MemoryMedia(
        bytes: bytes,
        info: MediaInfo(format: MediaFormat.unknown),
      ),
    );
    leases.add(lease);
    return Success(
      LoadResult(
        value: lease,
        origin: LoadOrigin.local,
        fetchedAt: DateTime.utc(2026),
      ),
    );
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

void main() {
  final fontRef = MediaRef(
    sourceId: SourceId('local'),
    mediaId: 'self-authored-font',
  );
  testWidgets(
    'font gate registers before measuring, shares load and releases leases',
    (tester) async {
      final family = EmbeddedFontFamily([fontRef]);
      final repository = _Media(syntheticFont(advance: 900))
        ..pending = Completer<void>();
      final registry = ReaderFontRegistry();
      final content = ChapterContent(
        key: ChapterKey(
          novelKey: LocalBookIdentity.book('a' * 64),
          chapterId: 'font',
        ),
        title: 'Font',
        blocks: [
          ParagraphBlock(
            text: 'AB',
            inlineStyles: [
              InlineTextStyle(start: 0, length: 2, fonts: [family]),
            ],
          ),
        ],
      );
      Widget gate() => ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => ReaderFontScope(
            registry: registry,
            child: ReaderFontGate(
              content: content,
              repository: repository,
              child: const Text('Ready'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(gate());
      expect(find.text('Ready'), findsNothing);
      // Leaving a chapter must not cancel an application-owned shared load.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(gate());
      repository.pending!.complete();
      await _frames(tester);
      expect(find.text('Ready'), findsOneWidget);
      expect(repository.calls, 1);
      expect(repository.modes, [ReadMode.cacheOnly]);
      expect(repository.leases.every((l) => l.isClosed), isTrue);
      final style = readerAuthoredStyle(
        const TextStyle(fontSize: 20, fontFamily: 'Ahem'),
        content.blocks.single.inlineStyles,
        0,
      );
      final painter = TextPainter(
        text: TextSpan(text: 'AB', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(painter.width, closeTo(36, .01));
      painter.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(gate());
      await _frames(tester);
      expect(repository.calls, 1);
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
    },
  );

  testWidgets(
    'unavailable embedded font falls back before native text appears',
    (tester) async {
      final family = EmbeddedFontFamily([
        MediaRef(sourceId: SourceId('local'), mediaId: 'missing-font'),
      ]);
      final repository = _Media(syntheticFont())..missing = true;
      final content = ChapterContent(
        key: ChapterKey(
          novelKey: LocalBookIdentity.book('a' * 64),
          chapterId: 'fallback',
        ),
        title: 'Fallback',
        blocks: [
          ParagraphBlock(
            text: 'AB',
            inlineStyles: [
              InlineTextStyle(start: 0, length: 2, fonts: [family]),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => ReaderFontGate(
              content: content,
              repository: repository,
              child: const Text('Fallback ready'),
            ),
          ),
        ),
      );
      await _frames(tester);
      expect(find.text('Fallback ready'), findsOneWidget);
      final style = readerAuthoredStyle(
        const TextStyle(fontSize: 20, fontFamily: 'Ahem'),
        content.blocks.single.inlineStyles,
        0,
      );
      final painter = TextPainter(
        text: TextSpan(text: 'AB', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(painter.width, closeTo(40, .01));
      painter.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final failed in [false, true]) {
    testWidgets(
      'background is decorative, clips radius, preserves ink and hit testing (failure=$failed)',
      (tester) async {
        final media = fixtureMediaRef(0);
        final repo = _Media(
          failed ? Uint8List.fromList([1, 2, 3]) : fixturePng(40, 20, 1),
        );
        final box = BlockBox(
          group: 1,
          radius: LayoutLength(12, LayoutUnit.px),
          backgroundImage: BlockBackgroundImage(
            media: media,
            intrinsicWidth: 40,
            intrinsicHeight: 20,
            width: LayoutLength(2, LayoutUnit.em),
            x: .5,
            y: .5,
          ),
        );
        final geometry = ReaderBoxGeometry(box, 200, 20, double.infinity);
        var taps = 0;
        Widget render(bool starts) => ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => Center(
              child: SizedBox(
                width: 200,
                child: ReaderBoxFrame(
                  box: box,
                  width: 200,
                  top: 0,
                  bottom: 0,
                  geometry: geometry,
                  starts: starts,
                  ends: true,
                  images: repo,
                  child: GestureDetector(
                    onTap: () => taps++,
                    child: ReaderLinkedText(
                      text: '2',
                      prefix: '',
                      blockOffset: 0,
                      links: const [],
                      style: const TextStyle(
                        fontFamily: 'Ahem',
                        fontSize: 20,
                        color: Colors.white,
                      ),
                      align: TextAlign.center,
                      scaler: TextScaler.noScaling,
                      hasBackgroundImage: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(render(true));
        await _frames(tester);
        expect(tester.takeException(), isNull);
        final rich = tester.widget<RichText>(find.byType(RichText).last);
        expect(
          rich.text.style!.color,
          failed ? isNot(Colors.white) : Colors.white,
        );
        expect(find.byType(RawImage), failed ? findsNothing : findsOneWidget);
        if (!failed) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byType(RichText).last,
          );
          final glyph = paragraph
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 1),
              )
              .single
              .toRect();
          expect(
            paragraph.localToGlobal(glyph.center).dx,
            closeTo(tester.getCenter(find.byType(ReaderBoxFrame)).dx, .01),
          );
          final rect = tester.getRect(find.byType(SourceImage));
          expect(rect.width, closeTo(40, .01));
          expect(rect.height, closeTo(20, .01));
          expect(
            rect.center.dx,
            closeTo(tester.getCenter(find.byType(ReaderBoxFrame)).dx, .01),
          );
          expect(
            tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
            BorderRadius.circular(12),
          );
        }
        await tester.tap(find.byType(ReaderLinkedText));
        expect(taps, 1);
        await tester.pumpWidget(render(false));
        await _frames(tester);
        expect(find.byType(SourceImage), findsNothing);
        expect(
          tester.widget<RichText>(find.byType(RichText).last).text.style!.color,
          isNot(Colors.white),
        );
        await tester.pumpWidget(const SizedBox());
        await _frames(tester);
        expect(repo.leases.every((l) => l.isClosed), isTrue);
      },
    );
  }
}
