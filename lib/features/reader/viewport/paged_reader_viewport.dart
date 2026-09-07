import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import 'page_layout.dart';
import 'render_chunk.dart';
import 'block_style.dart';

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

/// Horizontal native pivot slivers + PageScrollPhysics. Pages before/after the
/// semantic pivot are computed only when requested; no fictitious global page
/// number, no full-prefix layout, and no stored page index.
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
  });
  final ChapterContent content;
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
  @override
  State<PagedReaderViewport> createState() => _PagedReaderViewportState();
}

class _PagedReaderViewportState extends State<PagedReaderViewport> {
  final _scroll = ScrollController(keepScrollOffset: false);
  final _pages = <int, ReaderPage>{};
  final _center = const ValueKey('paged-forward');
  PageLayout? _layout;
  Object? _signature;
  ReaderPosition? _position;
  int _epoch = 0;
  int? _first;
  int? _last;
  bool _usedFallback = false;
  bool _userScrolling = false;
  bool _deferredLayout = false;
  bool _restoring = false;
  @override
  void initState() {
    super.initState();
    _attach();
    _position = widget.initialPosition;
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
    if (!_userScrolling) {
      _signature = null;
    } else {
      _deferredLayout = true;
    }
  }

  @override
  void dispose() {
    widget.controller._state = null;
    _scroll.dispose();
    super.dispose();
  }

  void _restore(ReaderPosition position) {
    if (!mounted) return;
    _restoring = true;
    widget.onRestoreStart?.call();
    setState(() {
      _position = position;
      _signature = null;
    });
  }

  ReaderPage? _page(int number) {
    final cached = _pages[number];
    if (cached != null) return cached;
    if ((_first != null && number < _first!) ||
        (_last != null && number > _last!)) {
      return null;
    }
    final nearest = _pages.keys.reduce(
      (a, b) => (a - number).abs() < (b - number).abs() ? a : b,
    );
    var current = nearest;
    while (current != number) {
      final forward = number > current;
      final page = forward
          ? _layout!.forward(_pages[current]!.end)
          : _layout!.backward(_pages[current]!.start);
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

  Future<void> _turn(int direction) async {
    if (!_scroll.hasClients || _layout == null) return;
    final current = (_scroll.offset / _layout!.width).round();
    if (_page(current + direction) == null) return;
    await _scroll.animateTo(
      (current + direction) * _layout!.width,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _sample() {
    if (_restoring || !_scroll.hasClients || _layout == null) return;
    final number = (_scroll.offset / _layout!.width).round();
    final page = _page(number);
    if (page == null) return;
    _position = _layout!.position(page.start);
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
      final direction = Directionality.of(context);
      final signature = (
        constraints.maxWidth,
        constraints.maxHeight,
        scaler,
        direction,
        widget.textStyle,
        widget.content,
        widget.maxChunkCodePoints,
        widget.paragraphSpacing,
      );
      if (_signature != signature) {
        _restoring = true;
        widget.onRestoreStart?.call();
        final index = ChunkIndex(
          widget.content,
          maxCodePoints: widget.maxChunkCodePoints,
        );
        _usedFallback = index.resolve(_position).usedFallback;
        _layout = PageLayout(
          index: index,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          style: widget.textStyle,
          paragraphSpacing: widget.paragraphSpacing,
          scaler: scaler,
          direction: direction,
          imageHeights: widget.imageHeights,
          imageExtent: widget.imageExtent,
        );
        final first = _layout!.forward(_layout!.cursor(_position));
        // No clipping a text line into a viewport shorter than that line.
        if (first == null) return const SizedBox.shrink();
        _pages.clear();
        _pages[0] = first;
        _first = null;
        _last = null;
        _position = _layout!.position(first.start);
        _epoch++;
        _signature = signature;
        final epoch = _epoch;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && epoch == _epoch && _restoring) {
            _restoring = false;
            _sample();
          }
        });
      }
      Widget? buildPage(BuildContext context, int number) {
        final page = _page(number);
        if (page == null) return null;
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final fragment in page.fragments)
                Semantics(
                  header:
                      widget.content.blocks[_layout!
                              .index
                              .chunks[fragment.unit]
                              .blockIndex]
                          is HeadingBlock,
                  child: SizedBox(
                    height: fragment.height,
                    child: fragment.text == ''
                        ? const SizedBox.shrink()
                        : fragment.text != null
                        ? Padding(
                            padding: EdgeInsets.only(
                              top: widget.paragraphSpacing / 2,
                              bottom: widget.paragraphSpacing / 2,
                              left: readerBlockIndent(
                                widget.content.blocks[_layout!
                                    .index
                                    .chunks[fragment.unit]
                                    .blockIndex],
                                widget.textStyle,
                                scaler,
                                constraints.maxWidth,
                                _layout!.index.chunks[fragment.unit].start == 0,
                              ),
                            ),
                            child: Text(
                              fragment.text!,
                              style: readerBlockStyle(
                                widget.content.blocks[_layout!
                                    .index
                                    .chunks[fragment.unit]
                                    .blockIndex],
                                widget.textStyle,
                              ),
                              textAlign: readerBlockAlign(
                                widget.content.blocks[_layout!
                                    .index
                                    .chunks[fragment.unit]
                                    .blockIndex],
                              ),
                              textScaler: scaler,
                            ),
                          )
                        : _object(context, fragment),
                  ),
                ),
            ],
          ),
        );
      }

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) {
          if (details.localPosition.dx < constraints.maxWidth * .3) {
            _turn(-1);
          } else if (details.localPosition.dx > constraints.maxWidth * .7) {
            _turn(1);
          } else {
            widget.onCenterTap?.call();
          }
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _userScrolling = true;
              _restoring = false;
            }
            if (notification is ScrollEndNotification) {
              _userScrolling = false;
              _sample();
              if (_deferredLayout) {
                _deferredLayout = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _signature = null;
                    });
                  }
                });
              }
            }
            return false;
          },
          child: CustomScrollView(
            key: ValueKey(_epoch),
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            center: _center,
            physics: const PageScrollPhysics(),
            cacheExtent: 0,
            slivers: [
              SliverFixedExtentList(
                itemExtent: constraints.maxWidth,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => buildPage(context, -1 - i),
                  addAutomaticKeepAlives: false,
                  addSemanticIndexes: false,
                ),
              ),
              SliverFixedExtentList(
                key: _center,
                itemExtent: constraints.maxWidth,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => buildPage(context, i),
                  addAutomaticKeepAlives: false,
                  addSemanticIndexes: false,
                ),
              ),
            ],
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
