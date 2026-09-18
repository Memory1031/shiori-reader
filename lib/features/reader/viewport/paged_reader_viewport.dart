import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import 'page_layout.dart';
import 'page_boundaries.dart';
import 'render_chunk.dart';
import 'block_style.dart';
import 'reader_box.dart';
import 'paper_turn.dart';
import '../reader_linked_text.dart';
import '../reader_margin.dart';
import '../../../domain/contracts/contracts.dart';

class PagedReaderController {
  _PagedReaderViewportState? _state;
  ReaderPosition? capture() => _state?._position;
  void restore(ReaderPosition position) => _state?._restore(position);
  Future<void> next() => _state?._turn(1) ?? Future.value();
  Future<void> previous() => _state?._turn(-1) ?? Future.value();
  int get measuredChunks => _state?._layout?.measuredChunks ?? 0;
  int get cachedPages => _state?._pages.length ?? 0;
  bool get usedFallback => _state?._usedFallback ?? false;
  bool get isRestoring => _state?._restoring ?? false;
}

/// Native pages with a shared blank-back paper fold. Pages before/after the
/// semantic pivot are computed only when requested; no fictitious global page
/// number. Explicit seeks scan unknown forward boundaries in batches; ordinary turns stay lazy.
class PagedReaderViewport extends StatefulWidget {
  const PagedReaderViewport({
    super.key,
    required this.content,
    required this.controller,
    this.initialPosition,
    this.textStyle = const TextStyle(fontSize: 20, height: 1.7),
    this.maxChunkCodePoints = 800,
    this.paragraphSpacing = 16,
    this.imageHeights = const {},
    this.imageExtent,
    this.imageBuilder,
    this.onPosition,
    this.onRestoreStart,
    this.onCenterTap,
    this.onBoundary,
    this.onTurning,
    this.onTurnVisual,
    this.pageSize,
    this.contentOrigin = Offset.zero,
    this.startAtEnd = false,
    this.contentLinks = const [],
    this.onLink,
    this.images,
    this.columns = 1,
    this.columnGap = readerColumnGap,
  }) : assert(columns == 1 || columns == 2),
       assert(columnGap >= 0);
  final ChapterContent content;
  final int columns;
  final double columnGap;
  final ImageRepository? images;
  final PagedReaderController controller;
  final ReaderPosition? initialPosition;
  final TextStyle textStyle;
  final int maxChunkCodePoints;
  final double paragraphSpacing;
  final void Function(ReaderPosition, bool)? onPosition;
  final VoidCallback? onRestoreStart;
  final Map<MediaRef, double> imageHeights;
  final double Function(ImageBlock)? imageExtent;
  final Widget Function(BuildContext, ImageBlock)? imageBuilder;
  final VoidCallback? onCenterTap;
  final ValueChanged<int>? onBoundary;
  final ValueChanged<bool>? onTurning;
  final void Function(double progress, int direction)? onTurnVisual;
  final Size? pageSize;
  final Offset contentOrigin;
  final bool startAtEnd;
  final List<LocalContentLink> contentLinks;
  final ValueChanged<LocalContentLink>? onLink;
  @override
  State<PagedReaderViewport> createState() => _PagedReaderViewportState();
}

class _PagedReaderViewportState extends State<PagedReaderViewport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turnAnimation;
  int _current = 0;
  int? _target;
  int _direction = 1;
  double _dragDistance = 0;
  final _pages = <int, ReaderPage>{};
  PageLayout? _layout;
  PageBoundaries? _boundaries;
  List<double>? _imageGeometry;
  bool _positionReset = false;
  bool _seeking = false;
  Widget? _lastReadyPage;
  Widget? _seekPreview;
  Object? _signature;
  ReaderPosition? _position;
  ReaderPosition? _restoreAnchor;
  int _epoch = 0;
  int? _first;
  int? _last;
  bool _usedFallback = false;
  bool _userScrolling = false;
  bool _deferredLayout = false;
  bool _restoring = false;
  // Keep chapter-end entry anchored through late image dimensions and other
  // reflows. A committed turn or explicit restore establishes a new anchor.
  bool _anchorAtEnd = false;
  @override
  void initState() {
    super.initState();
    _turnAnimation =
        AnimationController(vsync: this, duration: PaperTurnMotion.duration)
          ..addListener(
            () => widget.onTurnVisual?.call(_turnAnimation.value, _direction),
          );
    _attach();
    _position = widget.initialPosition;
    _anchorAtEnd = widget.startAtEnd;
  }

  void _attach() {
    if (widget.controller._state != null) {
      throw StateError('Paged controller already attached');
    }
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(PagedReaderViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._state = null;
      _attach();
    }
  }

  @override
  void dispose() {
    widget.controller._state = null;
    _turnAnimation.dispose();
    super.dispose();
  }

  void _restore(ReaderPosition position) {
    if (!mounted) return;
    _restoring = true;
    widget.onRestoreStart?.call();
    setState(() {
      _seekPreview = _lastReadyPage;
      _anchorAtEnd = false;
      _position = position;
      _positionReset = true;
      _seeking = false;
      _epoch++;
    });
  }

  void _readyAfterFrame(int epoch) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _epoch || !_restoring) return;
      _restoring = false;
      _sample();
    });
  }

  void _seekPage(
    int epoch,
    PageCursor cursor,
    ReaderPage? last, {
    PageCursor? target,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _epoch || !_seeking) return;
      final watch = Stopwatch()..start();
      var next = cursor;
      var latest = last;
      var done = false;
      for (var count = 0; count < 8; count++) {
        final page = _boundaries!.forward(next);
        if (page == null) {
          done = true;
          break;
        }
        latest = page;
        next = page.end;
        if (next.unit >= _layout!.index.chunks.length ||
            target != null && PageBoundaries.compare(next, target) > 0) {
          done = true;
          break;
        }
        if (watch.elapsedMicroseconds >= 4000) break;
      }
      setState(() {
        if (done) {
          _seeking = false;
          if (latest != null) {
            _pages[0] = latest;
            _position = _layout!.position(latest.start);
            if (latest.end.unit >= _layout!.index.chunks.length) _last = 0;
          }
        }
      });
      if (done) {
        if (latest != null) _readyAfterFrame(epoch);
      } else {
        _seekPage(epoch, next, latest, target: target);
      }
    });
  }

  ReaderPage? _page(int number) {
    final cached = _pages[number];
    if (cached != null) return cached;
    if ((_first != null && number < _first!) ||
        (_last != null && number > _last!)) {
      return null;
    }
    if (_pages.isEmpty) return null;
    final nearest = _pages.keys.reduce(
      (a, b) => (a - number).abs() < (b - number).abs() ? a : b,
    );
    var current = nearest;
    while (current != number) {
      final forward = number > current;
      final page = forward
          ? _boundaries!.forward(_pages[current]!.end)
          : _boundaries!.backward(_pages[current]!.start);
      if (page == null) {
        if (forward) {
          _last = current;
        } else {
          _first = current;
        }
        return null;
      }
      current += forward ? 1 : -1;
      _pages[current] = page;
    }
    return _pages[number];
  }

  Future<void> _finish(bool commit) async {
    final target = _target;
    if (target == null) return;
    final epoch = _epoch;
    final reduced = MediaQuery.disableAnimationsOf(context);
    try {
      await PaperTurnMotion.settle(
        _turnAnimation,
        target: commit ? 1 : 0,
        reduced: reduced,
      );
    } on TickerCanceled {
      return;
    }
    if (!mounted || epoch != _epoch) return;
    setState(() {
      if (commit) {
        _current = target;
        _anchorAtEnd = false;
      }
      _target = null;
      _userScrolling = false;
      _turnAnimation.value = 0;
      if (_deferredLayout) {
        _signature = null;
        _deferredLayout = false;
      }
    });
    widget.onTurning?.call(false);
    if (commit) _sample();
  }

  Future<void> _turn(int direction) async {
    if (_layout == null || _target != null || _restoring) return;
    if (_page(_current + direction) == null) {
      widget.onBoundary?.call(direction);
      return;
    }
    setState(() {
      _direction = direction;
      _target = _current + direction;
      _userScrolling = true;
    });
    widget.onTurning?.call(true);
    await _finish(true);
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_layout == null || _restoring || _turnAnimation.isAnimating) return;
    _dragDistance += details.delta.dx;
    final direction = _dragDistance < 0 ? 1 : -1;
    if (_target == null) {
      if (_page(_current + direction) == null) return;
      setState(() {
        _direction = direction;
        _target = _current + direction;
        _userScrolling = true;
      });
      widget.onTurning?.call(true);
    }
    _turnAnimation.value =
        (-_dragDistance *
                _direction /
                (widget.pageSize?.width ?? _layout!.width))
            .clamp(0.0, 1.0);
  }

  void _dragEnd(DragEndDetails details) {
    if (_turnAnimation.isAnimating) return;
    if (_target != null) {
      final velocity = -(details.primaryVelocity ?? 0) * _direction;
      _finish(velocity > 600 || velocity >= -600 && _turnAnimation.value > .28);
    } else if (_dragDistance.abs() >= 48 &&
        (_dragDistance.abs() >=
                (widget.pageSize?.width ?? _layout?.width ?? 360) * .28 ||
            (details.primaryVelocity ?? 0) * _dragDistance.sign > 600)) {
      widget.onBoundary?.call(_dragDistance < 0 ? 1 : -1);
    }
    _dragDistance = 0;
  }

  void _sample() {
    if (_restoring || _layout == null) return;
    final number = _current;
    final page = _page(number);
    if (page == null) return;
    _position = _current == 0 && _restoreAnchor != null
        ? _restoreAnchor
        : _layout!.position(page.start);
    widget.onPosition?.call(
      _position!,
      page.end.unit >= _layout!.index.chunks.length,
    );
    _pages.removeWhere((key, _) => (key - number).abs() > 3);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      // Text.rich inherits typography. Resolve it once so pagination measures
      // the exact same font, spacing, locale and height behavior it paints.
      final defaults = DefaultTextStyle.of(context);
      final textStyle = defaults.style
          .merge(widget.textStyle)
          .copyWith(inherit: false);
      final locale = Localizations.maybeLocaleOf(context);
      final heightBehavior =
          defaults.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context);
      final direction = Directionality.of(context);
      final columnWidth =
          (constraints.maxWidth - (widget.columns - 1) * widget.columnGap) /
          widget.columns;
      final signature = (
        constraints.maxWidth,
        constraints.maxHeight,
        scaler,
        direction,
        textStyle,
        locale,
        heightBehavior,
        widget.content,
        widget.maxChunkCodePoints,
        widget.paragraphSpacing,
        widget.columns,
        widget.columnGap,
      );
      final imageGeometry = [
        for (final block in widget.content.blocks.whereType<ImageBlock>())
          widget.imageExtent?.call(block) ??
              widget.imageHeights[block.media] ??
              (block.width != null && block.height != null
                  ? columnWidth * block.height! / block.width!
                  : 180.0),
      ];
      final changed =
          _signature != signature || !listEquals(_imageGeometry, imageGeometry);
      if (changed && _userScrolling) _deferredLayout = true;
      if ((changed && !_userScrolling) || _positionReset) {
        _restoring = true;
        widget.onRestoreStart?.call();
        if (changed) {
          _seekPreview = null;
          final index = ChunkIndex(
            widget.content,
            maxCodePoints: widget.maxChunkCodePoints,
          );
          _layout = PageLayout(
            index: index,
            width: columnWidth,
            columns: widget.columns,
            height: constraints.maxHeight,
            style: textStyle,
            locale: locale,
            textHeightBehavior: heightBehavior,
            paragraphSpacing: widget.paragraphSpacing,
            scaler: scaler,
            direction: direction,
            imageHeights: widget.imageHeights,
            imageExtent: widget.imageExtent,
          );
          _boundaries = PageBoundaries(_layout!);
          _imageGeometry = imageGeometry;
          _signature = signature;
        }
        _usedFallback = _layout!.index.resolve(_position).usedFallback;
        _turnAnimation.stop(canceled: true);
        _turnAnimation.value = 0;
        _target = null;
        _userScrolling = false;
        _deferredLayout = false;
        _positionReset = false;
        _current = 0;
        _pages.clear();
        _first = null;
        _last = null;
        final epoch = ++_epoch;
        _restoreAnchor = _anchorAtEnd || _usedFallback ? null : _position;
        final target = _anchorAtEnd ? null : _layout!.cursor(_position);
        final start = _boundaries!.seekStart(
          target ?? PageCursor(_layout!.index.chunks.length, 0),
        );
        if (target != null && PageBoundaries.compare(start, target) == 0) {
          _seeking = false;
          final first = _boundaries!.forward(start);
          if (first != null) {
            _pages[0] = first;
            _position = _layout!.position(first.start);
            _readyAfterFrame(epoch);
          }
        } else {
          _seeking = true;
          _seekPage(epoch, start, null, target: target);
        }
      }
      // Pending chapter-end seeks must not expose a provisional page or progress.
      if (_seeking) {
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_seekPreview != null)
                ExcludeSemantics(child: AbsorbPointer(child: _seekPreview!)),
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ),
        );
      }
      if (_pages.isEmpty) return const SizedBox.shrink();
      double textWidth(PageFragment fragment) => readerBlockWidth(
        widget.content.blocks[_layout!.index.chunks[fragment.unit].blockIndex],
        columnWidth,
        textStyle,
        scaler,
        direction,
        chapter: widget.content.key,
        locale: locale,
      );

      ContentBlock fragmentBlock(PageFragment f) =>
          widget.content.blocks[_layout!.index.chunks[f.unit].blockIndex];
      double fragmentInnerWidth(PageFragment f) =>
          readerBoxInnerWidth(fragmentBlock(f), columnWidth);
      Widget? buildPage(BuildContext context, int number) {
        final page = _page(number);
        if (page == null) return null;
        Widget column(List<PageFragment> fragments, double width) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final fragment in fragments)
              Semantics(
                header:
                    widget.content.blocks[_layout!
                            .index
                            .chunks[fragment.unit]
                            .blockIndex]
                        is HeadingBlock,
                child: ReaderBoxFrame(
                  box: fragmentBlock(fragment).box,
                  width: readerBoxOuterWidth(fragmentBlock(fragment), width),
                  top: fragment.boxTop,
                  bottom: fragment.boxBottom,
                  child: SizedBox(
                    height:
                        fragment.height - fragment.boxTop - fragment.boxBottom,
                    child: fragment.text == ''
                        ? const SizedBox.shrink()
                        : fragment.text != null
                        ? Padding(
                            padding: EdgeInsets.only(
                              left:
                                  (fragmentInnerWidth(fragment) -
                                      textWidth(fragment)) /
                                  2,
                              right:
                                  (fragmentInnerWidth(fragment) -
                                      textWidth(fragment)) /
                                  2,
                              top:
                                  readerBlockSpacing(
                                    widget.content.blocks[_layout!
                                        .index
                                        .chunks[fragment.unit]
                                        .blockIndex],
                                    widget.paragraphSpacing,
                                    chapter: widget.content.key,
                                  ) /
                                  2,
                              bottom:
                                  readerBlockSpacing(
                                    widget.content.blocks[_layout!
                                        .index
                                        .chunks[fragment.unit]
                                        .blockIndex],
                                    widget.paragraphSpacing,
                                    chapter: widget.content.key,
                                  ) /
                                  2,
                            ),
                            child: ReaderLinkedText(
                              locale: locale,
                              textHeightBehavior: heightBehavior,
                              images: widget.images,
                              authoredBackground: fragmentBlock(
                                fragment,
                              ).box?.backgroundColor,
                              inlineStyles: widget
                                  .content
                                  .blocks[_layout!
                                      .index
                                      .chunks[fragment.unit]
                                      .blockIndex]
                                  .inlineStyles,
                              inlineImages: widget
                                  .content
                                  .blocks[_layout!
                                      .index
                                      .chunks[fragment.unit]
                                      .blockIndex]
                                  .inlineImages,
                              onLink: widget.onLink,
                              text: fragment.text!,
                              blockOffset:
                                  _layout!.index.chunks[fragment.unit].start +
                                  fragment.start,
                              links: widget.contentLinks
                                  .where(
                                    (note) =>
                                        note.sourceBlockKey ==
                                        _layout!
                                            .index
                                            .chunks[fragment.unit]
                                            .blockKey,
                                  )
                                  .toList(),
                              prefix: readerIndentPrefix(
                                widget.content.blocks[_layout!
                                    .index
                                    .chunks[fragment.unit]
                                    .blockIndex],
                                _layout!.index.chunks[fragment.unit].start ==
                                        0 &&
                                    fragment.start == 0,
                                textWidth(fragment),
                                textStyle,
                                scaler,
                                chapter: widget.content.key,
                              ),
                              style: readerBlockStyle(
                                widget.content.blocks[_layout!
                                    .index
                                    .chunks[fragment.unit]
                                    .blockIndex],
                                textStyle,
                                chapter: widget.content.key,
                              ),
                              align: readerBlockAlign(
                                widget.content.blocks[_layout!
                                    .index
                                    .chunks[fragment.unit]
                                    .blockIndex],
                                chapter: widget.content.key,
                              ),
                              scaler: scaler,
                            ),
                          )
                        : _object(context, fragment),
                  ),
                ),
              ),
          ],
        );
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: widget.columns == 1 || page.fullWidth
              ? Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: page.fullWidth
                        ? constraints.maxWidth.clamp(0, readerMaxPageWidth)
                        : constraints.maxWidth,
                    child: column(
                      page.fragments,
                      page.fullWidth
                          ? constraints.maxWidth.clamp(0, readerMaxPageWidth)
                          : constraints.maxWidth,
                    ),
                  ),
                )
              : Row(
                  textDirection: TextDirection.ltr,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: column(
                        page.fragments
                            .take(page.columnBreak ?? page.fragments.length)
                            .toList(),
                        columnWidth,
                      ),
                    ),
                    VerticalDivider(
                      key: const ValueKey('reader-spread-gutter'),
                      width: widget.columnGap,
                      thickness: 1,
                      indent: 24,
                      endIndent: 24,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .10),
                    ),
                    Expanded(
                      child: column(
                        page.columnBreak == null
                            ? []
                            : page.fragments.skip(page.columnBreak!).toList(),
                        columnWidth,
                      ),
                    ),
                  ],
                ),
        );
      }

      _lastReadyPage = buildPage(context, _current);
      _seekPreview = null;
      return Semantics(
        key: const ValueKey('paper-reader-pages'),
        container: true,
        onScrollLeft: () => _turn(1),
        onScrollRight: () => _turn(-1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _dragDistance = 0,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          onHorizontalDragCancel: () {
            _dragDistance = 0;
            if (_target != null && !_turnAnimation.isAnimating) _finish(false);
          },
          onTapUp: (details) {
            if (details.localPosition.dx < constraints.maxWidth * .3) {
              _turn(-1);
            } else if (details.localPosition.dx > constraints.maxWidth * .7) {
              _turn(1);
            } else {
              widget.onCenterTap?.call();
            }
          },
          child: AnimatedBuilder(
            animation: _turnAnimation,
            builder: (context, _) => ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final number in [?_target, _current])
                    ExcludeSemantics(
                      key: ValueKey((widget.content.key, number)),
                      excluding: number != _current,
                      child: ClipPath(
                        clipper: number == _current
                            ? PaperTurnClipper(
                                _turnAnimation.value,
                                _direction,
                                pageSize: widget.pageSize,
                                contentOrigin: widget.contentOrigin,
                              )
                            : null,
                        child: ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: number == _current
                              ? _lastReadyPage!
                              : buildPage(context, number)!,
                        ),
                      ),
                    ),
                  if (widget.onTurnVisual == null)
                    PaperTurnFold(
                      progress: _turnAnimation.value,
                      direction: _direction,
                      paper: Theme.of(context).scaffoldBackgroundColor,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _object(BuildContext context, PageFragment fragment) {
    final block =
        widget.content.blocks[_layout!.index.chunks[fragment.unit].blockIndex];
    if (block is ImageBlock) {
      return widget.imageBuilder?.call(context, block) ??
          Center(child: Text(block.alt ?? ''));
    }
    return const Divider();
  }
}
