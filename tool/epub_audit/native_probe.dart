import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_audio.dart';
import 'package:shiori/features/reader/reader_ruby.dart';
import 'package:shiori/features/reader/reader_inline_stack.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_authored_colors.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import 'package:shiori/features/reader/epub_layout_page.dart';
import 'package:shiori/features/reader/svg_paper_art.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/reader/viewport/reader_box.dart';
import 'audit.dart';
import 'loss.dart';
import 'loss_model.dart';
import 'plan.dart';
import 'replay.dart';
import 'report.dart';

class ProbeOffline implements NovelRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Online access forbidden');
}

class ProbeBooks implements LocalBookStore, LocalPagePresentationRepository {
  ProbeBooks(this.snapshot);
  final ProducerSnapshot snapshot;
  @override
  Future<Result<LocalBookRecord?>> read(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async => Success(
    LocalBookRecord(
      content: snapshot.parsed.content,
      format: LocalBookFormat.epub,
      importedAt: DateTime.utc(2000),
    ),
  );
  @override
  Future<Result<Uint8List>> readMedia(
    MediaRef ref, {
    required CancellationToken cancellation,
  }) async => Success(snapshot.parsed.media[ref.mediaId.split('/').last]!);
  @override
  Future<Result<String?>> loadPagePresentation(
    ChapterKey chapter, {
    required CancellationToken cancellation,
  }) async => Success(snapshot.parser.presentations[chapter.chapterId]);
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Probe store is read-only');
}

class ProbeLease implements MediaLease {
  ProbeLease(this.data);
  @override
  final MediaData data;
  @override
  bool isClosed = false;
  @override
  MediaPersistence get persistence => MediaPersistence.memoryOnly;
  @override
  AppFailure? get persistenceFailure => null;
  @override
  Future<void> close() async {
    isClosed = true;
  }
}

class ProbeAudio implements AudioPlayback {
  final _events = StreamController<AudioPlaybackState>.broadcast();
  int plays = 0, stops = 0, closes = 0;
  @override
  Stream<AudioPlaybackState> get states => _events.stream;
  @override
  Future<Result<void>> play(MediaRef media, AudioFormat format) async {
    plays++;
    _events.add(AudioPlaybackState.playing);
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> pause() async {
    _events.add(AudioPlaybackState.paused);
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> resume() async {
    _events.add(AudioPlaybackState.playing);
    return const Success<void>(null);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> close() async {
    closes++;
    await _events.close();
  }
}

class ProbeMedia implements ImageRepository, AudioPlaybackFactory {
  ProbeMedia(this.bytes);
  final Map<String, Uint8List> bytes;
  final loads = <String>[];
  final supplied = <String>[];
  final players = <ProbeAudio>[];
  @override
  AudioPlayback createAudioPlayback() {
    final player = ProbeAudio();
    players.add(player);
    return player;
  }

  @override
  Future<Result<LoadResult<MediaLease>>> load(
    MediaRef ref, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    final hash = ref.mediaId.split('/').last;
    loads.add(hash);
    final b = bytes[hash];
    if (b == null) {
      return Failure(
        AppFailure(kind: FailureKind.notFound, operation: Operation.media),
      );
    }
    supplied.add(hash);
    return Success(
      LoadResult(
        value: ProbeLease(
          MemoryMedia(
            bytes: b,
            info: MediaInfo(format: MediaFormat.unknown, byteLength: b.length),
          ),
        ),
        origin: LoadOrigin.local,
        fetchedAt: DateTime.utc(2000),
        isStale: false,
      ),
    );
  }
}

String paintedText(InlineSpan span) {
  if (span is TextSpan) {
    return '${span.text ?? ''}${(span.children ?? []).map(paintedText).join()}';
  }
  if (span is WidgetSpan) {
    Widget child = span.child;
    if (child is GestureDetector) child = child.child!;
    if (child is ReaderRuby) return child.baseText;
    if (child is ReaderInlineStack) {
      return '${child.layout.upperText}\n${child.layout.lowerText}';
    }
    return '\uFFFC';
  }
  return '';
}

Rect renderedRect(RenderBox render) => MatrixUtils.transformRect(
  render.getTransformTo(null),
  Offset.zero & render.size,
);
Json rectJson(Rect r) => {
  'left': r.left,
  'top': r.top,
  'right': r.right,
  'bottom': r.bottom,
};
bool containsRect(Rect outer, Rect inner, {double epsilon = 1}) =>
    outer.inflate(epsilon).contains(inner.topLeft) &&
    outer.inflate(epsilon).contains(inner.bottomRight);

/// No arbitrary code or text becomes executable input. Test fault adapters are
/// callbacks owned by tests, never fields accepted by the command runner.
Future<Json> runNativeProbe(
  WidgetTester tester,
  ProducerSnapshot snapshot,
  VerificationTarget target,
  ProbeConfiguration configuration, {
  String? screenshot,
  String? font,
  Future<void> Function(WidgetTester)? testOnlyTamper,
  Future<void> Function(WidgetTester)? testOnlyAfterRestore,
  ProbeMedia? testOnlyMedia,
  bool testOnlyObserveLinks = true,
}) async {
  tester.view.physicalSize = Size(
    configuration.width.toDouble(),
    configuration.height.toDouble(),
  );
  tester.view.devicePixelRatio = 1;
  final priorPlatform = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  final media = testOnlyMedia ?? ProbeMedia(snapshot.parsed.media);
  final books = ProbeBooks(snapshot);
  final settings = FixtureSettingsStore();
  final library = FixtureLibraryRepository();
  final boundary = GlobalKey();
  final assertions = <String, dynamic>{};
  final activations = <LocalContentLink>[];
  final appliedFontFamilies = <String>{};
  final decodedImages = <Json>[];
  final layers = <EvidenceLayer, CheckStatus>{
    for (final layer in EvidenceLayer.values) layer: CheckStatus.notRun,
  };
  final chapters = [
    ...snapshot.parsed.content.chapters,
    ...snapshot.parsed.content.auxiliaryChapters,
  ];
  final key = target.chapterKey == null
      ? null
      : ChapterKey.fromJson(target.chapterKey!);
  final chapter = chapters.where((c) => c.key == key).firstOrNull;
  var complete = false;
  var observedPath = 'unrepresented';
  Future<void> settle() async {
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 8)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  }

  try {
    if (chapter == null) {
      return {
        'complete': false,
        'observedPath': observedPath,
        'reason': 'no_represented_target',
        'layers': {
          for (final e in layers.entries) wireName(e.key): wireName(e.value),
        },
        'assertions': assertions,
      };
    }
    if (font != null) {
      await tester.runAsync(() async {
        final bytes = await File(font).readAsBytes();
        if (bytes.length > 32 * 1024 * 1024) {
          throw const FormatException('Font budget');
        }
        final loader = FontLoader('Microsoft YaHei UI')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        assertions['testFontHash'] = digest(base64Encode(bytes));
      });
    }
    await settings.save(
      ReaderSettings(
        fontSize: configuration.fontSize.toDouble(),
        controlsHintSeen: true,
        pageTurn: PageTurnStyle.none,
        themeMode: configuration.theme == 'dark'
            ? ReaderThemeMode.dark
            : ReaderThemeMode.light,
      ),
      cancellation: CancellationSource().token,
    );
    await tester.pumpWidget(
      ShioriApp(
        locale: Locale(configuration.language),
        routes: AppRoutes(
          home: (_) => RepaintBoundary(
            key: boundary,
            child: BookReaderScreen(
              chapter: chapter.key,
              repository: LocalReadingRepository(
                local: books,
                online: ProbeOffline(),
              ),
              images: media,
              settings: settings,
              library: library,
              offline: true,
              contentLinkObserver: testOnlyObserveLinks
                  ? activations.add
                  : null,
              initialBlockKey: target.blockKey,
              startAtBeginning: target.blockKey == null,
            ),
          ),
        ),
      ),
    );
    await settle();
    if (find.byType(EpubLayoutPage).evaluate().isNotEmpty) {
      observedPath = 'presentation';
      layers[EvidenceLayer.readerPath] = CheckStatus.pass;
      assertions['nativeGeometry'] = 'not_run_selected_presentation';
      return {
        'complete': false,
        'observedPath': observedPath,
        'reason': 'native_widget_cannot_measure_platform_webview',
        'layers': {
          for (final e in layers.entries) wireName(e.key): wireName(e.value),
        },
        'assertions': assertions,
      };
    }
    if (find.byType(PagedReaderViewport).evaluate().isEmpty) {
      return {
        'complete': false,
        'observedPath': observedPath,
        'reason': 'reader_not_ready',
        'layers': {
          for (final e in layers.entries) wireName(e.key): wireName(e.value),
        },
        'assertions': assertions,
      };
    }
    observedPath = target.candidate.predictedPath == 'presentation'
        ? 'native_fallback'
        : 'native';
    layers[EvidenceLayer.readerPath] = CheckStatus.pass;
    if (observedPath == 'native_fallback') {
      assertions['fallbackReason'] =
          'presentation_not_selected_or_unavailable_in_widget_host';
    }
    final viewport = tester.widget<PagedReaderViewport>(
      find.byType(PagedReaderViewport).first,
    );
    final controller = viewport.controller;
    if (testOnlyTamper != null) await testOnlyTamper(tester);
    final expected = <String, String>{};
    final evaluated = auditParsed(
      snapshot.parser,
      snapshot.parsed,
      privateExpected: expected,
    );
    final sidecar = evaluated['readingLoss'] as Json;
    final sourceFacts = objectList(
      sidecar,
      'sourceFacts',
    ).map(SourceFact.fromJson).toList();
    final representationFacts = objectList(
      sidecar,
      'representations',
    ).map(RepresentationFact.fromJson).toList();
    final correspondences = objectList(
      sidecar,
      'correspondences',
    ).map(Correspondence.fromJson).toList();
    final sourceByBlock = <String, SourceFact>{};
    for (final f in sourceFacts.where((f) => f.kind == 'text')) {
      final match = correspondences
          .where((r) => r.sourceId == f.id && r.status == CheckStatus.pass)
          .firstOrNull;
      for (final id in match?.representationIds ?? <String>[]) {
        final representation = representationFacts
            .where((r) => r.id == id)
            .firstOrNull;
        if (representation?.blockKey != null &&
            jsonEncode(representation!.chapterKey) ==
                jsonEncode(chapter.key.toJson())) {
          sourceByBlock[representation.blockKey!] = f;
        }
      }
    }
    var geometryFailures = 0,
        characterFailures = 0,
        unknownGeometries = 0,
        contrastFailures = 0,
        atomicFailures = 0,
        paginationFailures = 0,
        visibleFragments = 0,
        sourceChecks = 0,
        mixedLineChecks = 0;
    final decorations = <Json>[];
    var reachedEnd = false, targetSeen = false;
    final pages = <Json>[], seen = <String>{}, priorEnds = <int, int>{};
    final initial = controller.capture();
    for (var pageNumber = 0; pageNumber < target.maxPages; pageNumber++) {
      final inspection = controller.inspectDisplayedPage();
      if (inspection == null) {
        paginationFailures++;
        break;
      }
      final page = inspection.page;
      final pageId =
          '${page.start.unit}:${page.start.offset}:${page.end.unit}:${page.end.offset}';
      if (!seen.add(pageId)) {
        paginationFailures++;
        break;
      }
      final beforeCounter = controller.measuredChunks,
          beforeCache = controller.cachedPages;
      controller.inspectDisplayedPage();
      if (beforeCounter != controller.measuredChunks ||
          beforeCache != controller.cachedPages) {
        throw StateError('Read-only inspection changed measurement');
      }
      final fragments = <Json>[];
      final viewRect = tester.getRect(find.byType(PagedReaderViewport).first);
      for (final f in page.fragments) {
        final chunk = inspection.chunks[f.unit];
        final block = chapter.blocks[chunk.blockIndex];
        final start = chunk.start + f.start, end = chunk.start + f.end;
        visibleFragments++;
        if (target.blockKey == block.blockKey ||
            target.blockKey == null &&
                target.candidate.location.domPath == 'document') {
          targetSeen = true;
        }
        if (priorEnds.containsKey(chunk.blockIndex) &&
            priorEnds[chunk.blockIndex] != start &&
            f.text != null) {
          paginationFailures++;
        }
        priorEnds[chunk.blockIndex] = end;
        final source = sourceByBlock[block.blockKey];
        final sourceText = source == null ? null : expected[source.id];
        final modelText = auditBlockText(block);
        final modelSlice = String.fromCharCodes(
          modelText.runes.skip(start).take(end - start),
        );
        if (sourceText != null && f.text != null) sourceChecks++;
        if (f.text != null && modelSlice != f.text) characterFailures++;
        if (sourceText != null &&
            f.text != null &&
            String.fromCharCodes(
                  sourceText.runes.skip(start).take(end - start),
                ) !=
                f.text) {
          characterFailures++;
        }
        final visible = find.descendant(
          of: find.byType(PagedReaderViewport).first,
          matching: find.byType(ReaderLinkedText),
        );
        var matchedPaint = false;
        for (final element in visible.evaluate()) {
          final widget = element.widget as ReaderLinkedText;
          if (f.text == null ||
              widget.blockOffset < start ||
              widget.blockOffset >= end) {
            continue;
          }
          if (!modelText.startsWith(
            widget.text,
            String.fromCharCodes(
              modelText.runes.take(widget.blockOffset),
            ).length,
          )) {
            continue;
          }
          final paints = find.descendant(
            of: find.byWidget(widget),
            matching: find.byType(RichText),
          );
          for (final paintElement in paints.evaluate()) {
            final render = paintElement.renderObject;
            if (render is! RenderParagraph || !render.hasSize) continue;
            final actual = paintedText(render.text);
            void observeFont(InlineSpan span) {
              if (span.style?.fontFamily != null) {
                appliedFontFamilies.add(digest(span.style!.fontFamily!));
              }
              if (span is TextSpan) {
                for (final child in span.children ?? <InlineSpan>[]) {
                  observeFont(child);
                }
              }
            }

            observeFont(render.text);
            if (actual != '${widget.prefix}${widget.text}') {
              if (widget.inlineRuby.isEmpty &&
                  widget.inlineStacks.isEmpty &&
                  widget.flow == null) {
                characterFailures++;
              }
              continue;
            }
            matchedPaint = true;
            final boxes = render.getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: render.text.toPlainText().length,
              ),
            );
            if (boxes.isEmpty && widget.text.trim().isNotEmpty) {
              geometryFailures++;
            }
            for (final box in boxes) {
              final rect = MatrixUtils.transformRect(
                render.getTransformTo(null),
                box.toRect(),
              );
              if (!containsRect(viewRect, rect)) geometryFailures++;
            }
            final colors = ReaderAuthoredColors(Theme.of(element));
            var background = widget.authoredBackground == null
                ? colors.paper
                : colors.resolve(
                    Color(widget.authoredBackground!),
                    ReaderColorRole.background,
                  );
            var complexBackground = widget.hasBackgroundImage;
            element.visitAncestorElements((ancestor) {
              final paint = ancestor.widget;
              if (paint is CustomPaint && paint.painter is ReaderBoxPainter) {
                final painter = paint.painter! as ReaderBoxPainter;
                complexBackground |= painter.box.backgroundImage != null;
                if (painter.box.backgroundColor != null) {
                  background = painter.colors.resolve(
                    Color(painter.box.backgroundColor!),
                    ReaderColorRole.background,
                  );
                }
                return false;
              }
              return true;
            });
            if (complexBackground || background.a < 1) {
              unknownGeometries++;
            } else {
              void color(InlineSpan span, Color? inherited) {
                if (span is! TextSpan) return;
                final foreground = span.style?.color ?? inherited;
                if (foreground != null &&
                    foreground.a == 1 &&
                    (span.text ?? '').trim().isNotEmpty &&
                    readerColorContrast(foreground, background) < 1.5) {
                  contrastFailures++;
                }
                for (final child in span.children ?? <InlineSpan>[]) {
                  color(child, foreground);
                }
              }

              color(render.text, widget.style.color ?? colors.ink);
            }
          }
        }
        if (f.text != null && f.text!.trim().isNotEmpty && !matchedPaint) {
          unknownGeometries++;
        }
        for (final range in [
          ...block.inlineRuby.map((r) => (r.start, r.end)),
          ...block.inlineStacks.map((s) => (s.start, s.end)),
        ]) {
          if (range.$1 < end &&
              range.$2 > start &&
              (range.$1 < start || range.$2 > end)) {
            atomicFailures++;
          }
        }
        fragments.add({
          'blockKey': block.blockKey,
          'start': start,
          'end': end,
          'unit': 'unicode_code_point',
          'paintedModelHash': f.text == null ? null : digest(f.text!),
          'independentSourceChecked': sourceText != null,
          'height': f.height,
          'mixedLineHeights': f.flow?.lines.map((l) => l.height).toList(),
        });
      }
      for (final type in [ReaderRuby, ReaderInlineStack]) {
        for (final element
            in find
                .descendant(
                  of: find.byType(PagedReaderViewport).first,
                  matching: find.byType(type),
                )
                .evaluate()) {
          final render = element.renderObject;
          if (render is RenderBox && render.hasSize) {
            final atom = renderedRect(render);
            if (!containsRect(viewRect, atom)) atomicFailures++;
            // Mixed-line containment is observed in the actual parent paragraph,
            // including placeholder ascent/descent, not a standalone atom probe.
            element.visitAncestorElements((ancestor) {
              final paragraph = ancestor.renderObject;
              if (paragraph is RenderParagraph && paragraph.hasSize) {
                mixedLineChecks++;
                if (!containsRect(renderedRect(paragraph), atom)) {
                  atomicFailures++;
                }
                return false;
              }
              return true;
            });
          }
        }
      }
      for (final e
          in find
              .descendant(
                of: find.byType(PagedReaderViewport).first,
                matching: find.byType(CustomPaint),
              )
              .evaluate()) {
        final render = e.renderObject;
        if (render is RenderCustomPaint &&
            render.painter is ReaderBoxPainter &&
            render.hasSize &&
            decorations.length < 32) {
          final measured = await tester.runAsync(
            () => borderPixels(render.painter!, render.size),
          );
          decorations.add(measured!);
          if (measured['status'] == 'fail') geometryFailures++;
        }
      }
      pages.add({
        'cursor': pageId,
        'fragments': fragments,
        'columns': inspection.columns,
      });
      for (final element
          in find
              .descendant(
                of: find.byType(PagedReaderViewport).first,
                matching: find.byType(RawImage),
              )
              .evaluate()) {
        final widget = element.widget as RawImage;
        final render = element.renderObject;
        if (widget.image != null &&
            render is RenderBox &&
            render.hasSize &&
            decodedImages.length < 32) {
          final rect = renderedRect(render);
          decodedImages.add({
            'naturalWidth': widget.image!.width,
            'naturalHeight': widget.image!.height,
            'rect': rectJson(rect),
            'visibleInViewport': containsRect(viewRect, rect),
          });
          if (!containsRect(viewRect, rect)) atomicFailures++;
        }
      }
      if (page.end.unit >= inspection.chunks.length) {
        reachedEnd = true;
        break;
      }
      await controller.next();
      await settle();
    }
    if (pages.length > 1) {
      await controller.previous();
      await settle();
      final page = controller.inspectDisplayedPage()?.page;
      final expectedPage = pages[pages.length - 2]['cursor'];
      if (page == null ||
          '${page.start.unit}:${page.start.offset}:${page.end.unit}:${page.end.offset}' !=
              expectedPage) {
        paginationFailures++;
      }
    }
    var restored = false;
    if (initial != null) {
      controller.restore(initial);
      await settle();
      if (testOnlyAfterRestore != null) await testOnlyAfterRestore(tester);
      final inspection = controller.inspectDisplayedPage();
      restored =
          inspection?.page.fragments.any((f) {
            final chunk = inspection.chunks[f.unit];
            final offset = (initial.blockFraction * chunk.total).round();
            return chunk.blockKey == initial.blockKey &&
                offset >= chunk.start + f.start &&
                (offset < chunk.start + f.end || chunk.total == 0);
          }) ==
          true;
    }
    assertions['screenshotPhase'] = 'after_restore_before_input';
    if (screenshot != null && target.maxScreenshots > 0) {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png!.lengthInBytes > target.maxEvidenceBytes) {
            throw const FormatException('Screenshot budget');
          }
          await File(
            screenshot,
          ).writeAsBytes(png.buffer.asUint8List(), flush: true);
        } finally {
          image.dispose();
        }
      });
    }
    var clickChecks = 0, clickFailures = 0;
    // Actual hit testing into the native control; fake only substitutes the
    // platform playback resource. No speaker/decoder verification is claimed.
    final controls = find.byType(ReaderAudioControl);
    if (controls.evaluate().isNotEmpty) {
      final button = find.descendant(
        of: controls.first,
        matching: find.byType(IconButton),
      );
      if (button.evaluate().isNotEmpty &&
          tester.widget<IconButton>(button.first).onPressed != null) {
        clickChecks++;
        await tester.tap(button.first);
        await settle();
        if (media.players.fold<int>(0, (n, p) => n + p.plays) != 1) {
          clickFailures++;
        }
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle();
        assertions['audioStopTrigger'] = 'platform_lifecycle_pause';
        if (media.players.fold<int>(0, (n, p) => n + p.stops) != 1) {
          clickFailures++;
        }
      }
    }
    final linked = find.descendant(
      of: find.byType(PagedReaderViewport).first,
      matching: find.byType(ReaderLinkedText),
    );
    final selectedLink = linked
        .evaluate()
        .map((e) => e.widget as ReaderLinkedText)
        .where(
          (w) => w.links.any(
            (l) =>
                l.sourceOffset != null &&
                l.sourceLength != null &&
                !l.isFootnote,
          ),
        )
        .firstOrNull;
    if (selectedLink != null &&
        selectedLink.flow == null &&
        selectedLink.inlineRuby.isEmpty &&
        selectedLink.inlineStacks.isEmpty) {
      final link = selectedLink.links.firstWhere(
        (l) =>
            l.sourceOffset != null && l.sourceLength != null && !l.isFootnote,
      );
      final paints = find.descendant(
        of: find.byWidget(selectedLink),
        matching: find.byType(RichText),
      );
      if (paints.evaluate().isNotEmpty) {
        final render = tester.renderObject<RenderParagraph>(paints.first);
        final start = (link.sourceOffset! - selectedLink.blockOffset).clamp(
          0,
          selectedLink.text.runes.length,
        );
        final end = (start + link.sourceLength!).clamp(
          start,
          selectedLink.text.runes.length,
        );
        final utfStart =
            selectedLink.prefix.length +
            String.fromCharCodes(selectedLink.text.runes.take(start)).length;
        final utfEnd =
            selectedLink.prefix.length +
            String.fromCharCodes(selectedLink.text.runes.take(end)).length;
        final boxes = render.getBoxesForSelection(
          TextSelection(baseOffset: utfStart, extentOffset: utfEnd),
        );
        if (boxes.isNotEmpty) {
          clickChecks++;
          final beforeActivations = activations.length;
          await tester.tapAt(render.localToGlobal(boxes.first.toRect().center));
          await settle();
          if (activations.length != beforeActivations + 1 ||
              activations.last != link) {
            clickFailures++;
          }
          final current = tester
              .widgetList<ReaderContentView>(find.byType(ReaderContentView))
              .where((v) => v.active)
              .firstOrNull;
          if (link.target != null &&
              (current?.content.key != link.target ||
                  link.targetBlockKey != null &&
                      current?.viewportController?.capture()?.blockKey !=
                          link.targetBlockKey)) {
            clickFailures++;
          }
        }
      }
    }
    complete = reachedEnd && targetSeen;
    layers[EvidenceLayer.sourceModel] = characterFailures > 0
        ? CheckStatus.fail
        : sourceChecks == 0
        ? CheckStatus.unknown
        : CheckStatus.pass;
    layers[EvidenceLayer.widgetGeometry] =
        geometryFailures + atomicFailures + contrastFailures > 0
        ? CheckStatus.fail
        : targetSeen && unknownGeometries == 0
        ? CheckStatus.pass
        : CheckStatus.unknown;
    layers[EvidenceLayer.controlRouting] = clickFailures > 0
        ? CheckStatus.fail
        : clickChecks > 0
        ? CheckStatus.pass
        : CheckStatus.notRun;
    final expectedFamilies = chapter.blocks
        .expand((block) => block.inlineStyles)
        .expand((style) => style.fonts)
        .map((font) => digest(font.familyName))
        .toSet();
    if (expectedFamilies.isNotEmpty) {
      layers[EvidenceLayer.fontGlyph] = CheckStatus.unknown;
    }
    assertions.addAll({
      'pages': pages,
      'reachedDocumentEnd': reachedEnd,
      'targetVisible': targetSeen,
      'partial': !complete,
      'visibleFragments': visibleFragments,
      'characterIdentityFailures': characterFailures,
      'geometryFailures': geometryFailures,
      'unknownGeometry': unknownGeometries,
      'atomicFailures': atomicFailures,
      'mixedLineChecks': mixedLineChecks,
      'decorationPixels': decorations,
      'lowContrastFailures': contrastFailures,
      'paginationFailures': paginationFailures,
      'restoreVisible': restored,
      'inputChecks': clickChecks,
      'inputFailures': clickFailures,
      'linkActivations': activations.length,
      'resourceLoads': media.loads.toSet().toList(),
      'decodedImages': decodedImages,
      'fonts': {
        'loadRequestsObserved': media.loads
            .where(
              (hash) => chapter.blocks.any(
                (block) => block.inlineStyles.any(
                  (style) => style.fonts.any(
                    (font) => font.sources.any(
                      (ref) => ref.mediaId.split('/').last == hash,
                    ),
                  ),
                ),
              ),
            )
            .length,
        'resourceBytesSupplied': media.supplied
            .where(
              (hash) => chapter.blocks.any(
                (block) => block.inlineStyles.any(
                  (style) => style.fonts.any(
                    (font) => font.sources.any(
                      (ref) => ref.mediaId.split('/').last == hash,
                    ),
                  ),
                ),
              ),
            )
            .length,
        'glyphAttribution': 'unknown',
        'expectedFamilyHashes': expectedFamilies.toList(),
        'renderedSpanFamilyHashes': appliedFontFamilies.toList(),
        'allObservedDeclarationsOnSpan': expectedFamilies.isEmpty
            ? null
            : appliedFontFamilies.containsAll(expectedFamilies),
        'testDefaultFont': font == null
            ? 'Ahem_widget_test'
            : 'explicit_loaded_font',
      },
      'audioDecode': 'not_run_fake_platform_no_sound',
    });
    if (paginationFailures > 0 || !restored) {
      layers[EvidenceLayer.widgetGeometry] = CheckStatus.fail;
    }
    if (tester.takeException() != null) {
      layers[EvidenceLayer.widgetGeometry] = CheckStatus.fail;
      assertions['flutterError'] = 'render_or_layout_error';
    }
    return {
      'complete': complete,
      'observedPath': observedPath,
      'reason': complete
          ? 'executed'
          : 'page_budget_or_target_coverage_partial',
      'layers': {
        for (final e in layers.entries) wireName(e.key): wireName(e.value),
      },
      'assertions': assertions,
    };
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    assertions['audioStops'] = media.players.fold<int>(
      0,
      (n, p) => n + p.stops,
    );
    assertions['audioCloses'] = media.players.fold<int>(
      0,
      (n, p) => n + p.closes,
    );
    await library.close();
    await books.close();
    debugDefaultTargetPlatformOverride = priorPlatform;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Future<String> prepareBrowserDocument(
  ProducerSnapshot snapshot,
  VerificationTarget target,
  ProbeConfiguration config,
) async {
  final key = target.chapterKey == null
      ? null
      : ChapterKey.fromJson(target.chapterKey!);
  final html = snapshot.parser.presentations[key?.chapterId];
  if (html == null) throw const FormatException('No production presentation');
  final theme = readerTheme(
    ReaderSettings(
      themeMode: config.theme == 'dark'
          ? ReaderThemeMode.dark
          : ReaderThemeMode.light,
    ),
    Brightness.light,
  );
  final ink = theme.colorScheme.onSurface;
  final prepared = await themedSvgPaperArtwork(html, ink);
  return epubLayoutDocument(
    prepared,
    theme.scaffoldBackgroundColor,
    ink,
    theme.brightness,
    true,
  );
}

Future<Json> borderPixels(CustomPainter painter, Size size) async {
  if (painter is! ReaderBoxPainter || size.width > 1920 || size.height > 1600) {
    return {'status': 'unknown', 'reason': 'non_simple_or_oversized_painter'};
  }
  final g = painter.geometry;
  final width = math.min(g.borderTop, g.borderLeft);
  final radius = g.radius.clamp(0.0, math.min(size.width, size.height) / 2);
  if (radius < 6 ||
      width < 2 ||
      !painter.top ||
      painter.box.backgroundImage != null ||
      painter.box.borders?.top?.style == BoxBorderStyle.dashed ||
      painter.box.borders?.top?.style == BoxBorderStyle.dotted) {
    return {'status': 'unknown', 'reason': 'not_solid_closed_rounded_corner'};
  }
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  try {
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final innerRadius = radius - width / 2;
    final point = (radius - innerRadius / math.sqrt2).round();
    final alpha = bytes[(point * image.width + point) * 4 + 3];
    final outsideAlpha = bytes[3];
    final background = painter.box.backgroundColor == null
        ? null
        : painter.colors.resolve(
            Color(painter.box.backgroundColor!),
            ReaderColorRole.background,
          );
    final border = painter.colors.resolve(
      Color(
        painter.box.borders?.top?.color ??
            painter.box.borderColor ??
            0xff808080,
      ),
      ReaderColorRole.border,
      background: background,
    );
    final index = (point * image.width + point) * 4;
    final arc = Color.fromARGB(
      bytes[index + 3],
      bytes[index],
      bytes[index + 1],
      bytes[index + 2],
    );
    final borderMatches =
        (arc.r - border.r).abs() < .2 &&
        (arc.g - border.g).abs() < .2 &&
        (arc.b - border.b).abs() < .2;
    return {
      'status': alpha > 80 && outsideAlpha < 30 && borderMatches
          ? 'pass'
          : 'fail',
      'cornerAlpha': alpha,
      'outsideCornerAlpha': outsideAlpha,
      'arcMatchesBorder': borderMatches,
      'pixel': [point, point],
      'radius': radius,
      'sideWidth': width,
    };
  } finally {
    image.dispose();
    picture.dispose();
  }
}
