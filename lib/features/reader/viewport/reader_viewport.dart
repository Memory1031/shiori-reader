import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../domain/models/models.dart';
import '../position/position_resolver.dart';
import 'render_chunk.dart';
import 'block_style.dart';

/// The caller owns the controller. It stores semantic positions, not durable
/// pixel offsets; diagnostics count only mounted lazy render children.
class ReaderViewportController {
  _ReaderViewportState? _state;
  ReaderPosition? capture() => _state?._capture();
  void restore(ReaderPosition position) => _state?._restore(position);
  bool get isRestoring => _state?._restoring ?? false;
  bool get usedFallback => _state?._usedFallback ?? false;
  int get mountedCount => _state?._boxes.length ?? 0;
  int get buildCount => _state?._buildCount ?? 0;
  List<int> get visibleBlocks =>
      _state
          ?._visible()
          .map((e) => _state!._index.chunks[e.$1].blockIndex)
          .toSet()
          .toList() ??
      [];
  double? blockTop(int blockIndex) => _state?._topForBlock(blockIndex);
}

typedef ReaderImageBuilder =
    Widget Function(BuildContext context, ImageBlock image);

class ReaderViewport extends StatefulWidget {
  const ReaderViewport({
    super.key,
    required this.content,
    required this.controller,
    this.initialPosition,
    this.textStyle = const TextStyle(fontSize: 20, height: 1.7),
    this.maxChunkCodePoints = 800,
    this.paragraphSpacing = 16,
    this.imageBuilder,
    this.onPosition,
    this.onRestoreStart,
  });
  final ChapterContent content;
  final ReaderViewportController controller;
  final ReaderPosition? initialPosition;
  final TextStyle textStyle;
  final int maxChunkCodePoints;
  final double paragraphSpacing;
  final void Function(ReaderPosition, bool)? onPosition;
  final VoidCallback? onRestoreStart;
  final ReaderImageBuilder? imageBuilder;
  @override
  State<ReaderViewport> createState() => _ReaderViewportState();
}

class _ReaderViewportState extends State<ReaderViewport> {
  final _viewport =
      GlobalKey(); // One viewport key, never one per domain block.
  final _center = const ValueKey('reader-forward');
  final _scroll = ScrollController(keepScrollOffset: false);
  final _boxes = <int, _TrackedBox>{};
  late ChunkIndex _index;
  ReaderPosition? _last;
  ReaderPosition? _target;
  int _pivot = 0;
  int _epoch = 0;
  int _interaction = 0;
  int _buildCount = 0;
  bool _restoring = true;
  bool _usedFallback = false;
  bool _scheduled = false;
  bool _userScrolling = false;
  Object? _layout;
  double _width = 1;
  late TextScaler _scaler;
  late TextDirection _direction;
  @override
  void initState() {
    super.initState();
    _attach();
    _index = ChunkIndex(
      widget.content,
      maxCodePoints: widget.maxChunkCodePoints,
    );
    _target = widget.initialPosition ?? _index.position(0, 0);
    _select(_target!);
    _scroll.addListener(_scheduleSample);
  }

  void _attach() {
    if (widget.controller._state != null) {
      throw StateError('Viewport controller already attached');
    }
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(ReaderViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._state = null;
      _attach();
    }
    final anchor = _last ?? _target;
    if (oldWidget.content != widget.content ||
        oldWidget.maxChunkCodePoints != widget.maxChunkCodePoints) {
      _index = ChunkIndex(
        widget.content,
        maxCodePoints: widget.maxChunkCodePoints,
      );
    }
    if (!_userScrolling && anchor != null) _select(anchor);
  }

  @override
  void dispose() {
    widget.controller._state = null;
    _scroll.dispose();
    super.dispose();
  }

  void _select(ReaderPosition position) {
    widget.onRestoreStart?.call();
    final resolved = _index.resolve(position);
    _pivot = resolved.chunk;
    _usedFallback = resolved.usedFallback;
    _target = _index.position(_pivot, resolved.fraction);
    _restoring = true;
    _epoch++;
    _scheduleSample();
  }

  void _restore(ReaderPosition position) {
    if (!mounted) return;
    setState(() => _select(position));
  }

  RenderBox? get _view =>
      _viewport.currentContext?.findRenderObject() as RenderBox?;
  double _top(_TrackedBox box) =>
      box.localToGlobal(Offset.zero, ancestor: _view).dy;
  List<(int, _TrackedBox)> _visible() {
    final view = _view;
    if (view == null || !view.hasSize) return [];
    final entries = <(int, _TrackedBox)>[];
    for (final entry in _boxes.entries) {
      final box = entry.value;
      if (!box.attached || !box.hasSize) continue;
      final top = _top(box);
      if (top < view.size.height && top + box.size.height > 0.5) {
        entries.add((entry.key, box));
      }
    }
    entries.sort((a, b) => _top(a.$2).compareTo(_top(b.$2)));
    return entries;
  }

  double? _topForBlock(int index) {
    for (final entry in _visible()) {
      if (_index.chunks[entry.$1].blockIndex == index) return _top(entry.$2);
    }
    return null;
  }

  String _prefix(RenderChunk chunk, double width) => readerIndentPrefix(
    widget.content.blocks[chunk.blockIndex],
    chunk.start == 0,
    width,
    widget.textStyle,
    _scaler,
  );
  TextStyle _style(RenderChunk chunk) => readerBlockStyle(
    widget.content.blocks[chunk.blockIndex],
    widget.textStyle,
  );
  TextAlign _align(RenderChunk chunk) =>
      readerBlockAlign(widget.content.blocks[chunk.blockIndex]);
  TextPainter _painter(RenderChunk chunk, double width) => TextPainter(
    text: TextSpan(
      text: _prefix(chunk, width) + (chunk.text ?? ''),
      style: _style(chunk),
    ),
    textDirection: _direction,
    textScaler: _scaler,
    textAlign: _align(chunk),
  )..layout(maxWidth: width.clamp(1, double.infinity));
  ReaderPosition? _capture() {
    if (_restoring) return _target;
    final visible = _visible();
    if (visible.isEmpty) {
      // The trailing spacer allows the final block to leave the top edge.
      // A fast fling can reach it without an intermediate visible sample.
      if (_atEnd) return _last = _index.position(_index.chunks.length - 1, 1);
      return _last;
    }
    final (unit, box) = visible.first;
    final chunk = _index.chunks[unit];
    final y = (-_top(box)).clamp(0.0, box.size.height);
    double fraction;
    if (chunk.text != null && chunk.total > 0) {
      final painter = _painter(chunk, box.size.width);
      try {
        final position = painter.getPositionForOffset(
          Offset(
            0,
            (y -
                        readerBlockSpacing(
                              widget.content.blocks[chunk.blockIndex],
                              widget.paragraphSpacing,
                            ) /
                            2)
                    .clamp(0, double.infinity) +
                painter.preferredLineHeight * .5,
          ),
        );
        final line = painter.getLineBoundary(position);
        final codePoints = chunk.text!
            .substring(
              0,
              (line.start - _prefix(chunk, box.size.width).length).clamp(
                0,
                chunk.text!.length,
              ),
            )
            .runes
            .length;
        fraction = (chunk.start + codePoints) / chunk.total;
      } finally {
        painter.dispose();
      }
    } else {
      fraction = chunk.text == null ? y / box.size.height : 0;
    }
    return _last = _index.position(unit, fraction);
  }

  bool get _atEnd =>
      _scroll.hasClients &&
      _scroll.offset >= _scroll.position.maxScrollExtent - .5;

  void _geometryChanged() {
    if (!mounted || _restoring || _userScrolling || _last == null) return;
    final anchor = _last!;
    final interaction = _interaction;
    // RenderObject callbacks occur during layout; defer all state changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_restoring &&
          !_userScrolling &&
          interaction == _interaction) {
        _restore(anchor);
      }
    });
  }

  void _scheduleSample() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (_restoring) {
        final box = _boxes[_pivot];
        if (box == null || !box.hasSize || !_scroll.hasClients) return;
        final chunk = _index.chunks[_pivot];
        var within = _target!.blockFraction * box.size.height;
        if (chunk.text != null) {
          final cp =
              (readerCharacterOffset(_target!.blockFraction, chunk.total) -
                      chunk.start)
                  .clamp(
                    0,
                    (chunk.end - chunk.start - 1).clamp(0, chunk.total),
                  );
          final utf16 = String.fromCharCodes(chunk.text!.runes.take(cp)).length;
          final painter = _painter(chunk, box.size.width);
          try {
            within =
                readerBlockSpacing(
                      widget.content.blocks[chunk.blockIndex],
                      widget.paragraphSpacing,
                    ) /
                    2 +
                painter
                    .getOffsetForCaret(
                      TextPosition(
                        offset: utf16 + _prefix(chunk, box.size.width).length,
                      ),
                      Rect.zero,
                    )
                    .dy;
          } finally {
            painter.dispose();
          }
        }
        final desired = (_scroll.offset + _top(box) + within).clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        );
        _scroll.jumpTo(desired);
        _restoring = false;
        _scheduleSample();
      } else {
        final position = _capture();
        if (position != null) {
          final last = _boxes[_index.chunks.length - 1];
          final viewport =
              _viewport.currentContext?.findRenderObject() as RenderBox?;
          final completed =
              _atEnd ||
              (last != null &&
                  viewport != null &&
                  _top(last) + last.size.height <= viewport.size.height + 1);
          widget.onPosition?.call(position, completed);
        }
      }
    });
  }

  Widget _cell(BuildContext context, int unit) {
    _buildCount++;
    final chunk = _index.chunks[unit];
    final block = widget.content.blocks[chunk.blockIndex];
    Widget body;
    if (chunk.text == '') {
      body = const SizedBox(height: 16);
    } else if (chunk.text != null) {
      body = Padding(
        padding: EdgeInsets.only(
          top:
              readerBlockSpacing(
                widget.content.blocks[chunk.blockIndex],
                widget.paragraphSpacing,
              ) /
              2,
          bottom:
              readerBlockSpacing(
                widget.content.blocks[chunk.blockIndex],
                widget.paragraphSpacing,
              ) /
              2,
        ),
        child: Text(
          key: ValueKey('reader-text-$unit'),
          _prefix(chunk, _width) + chunk.text!,
          style: _style(chunk),
          textAlign: _align(chunk),
          textScaler: _scaler,
        ),
      );
    } else if (block is ImageBlock) {
      body =
          widget.imageBuilder?.call(context, block) ??
          SizedBox(height: 180, child: Center(child: Text(block.alt ?? '')));
    } else {
      body = const SizedBox(height: 24, child: Divider());
    }
    return IndexedSemantics(
      index: unit,
      child: Semantics(
        sortKey: OrdinalSortKey(unit.toDouble()),
        header: block is HeadingBlock,
        child: _Tracked(
          onAttach: (box) => _boxes[unit] = box,
          onDetach: (box) {
            if (identical(_boxes[unit], box)) _boxes.remove(unit);
          },
          onChanged: _geometryChanged,
          child: body,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth;
      _scaler = MediaQuery.textScalerOf(context);
      _direction = Directionality.of(context);
      final layout = (
        constraints.maxWidth,
        constraints.maxHeight,
        _scaler,
        _direction,
        widget.textStyle,
      );
      if (_layout != null && _layout != layout && !_userScrolling) {
        _select(_last ?? _target!);
      }
      _layout = layout;
      _scheduleSample();
      return SizedBox(
        key: _viewport,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _userScrolling = true;
              _interaction++;
              _restoring = false;
            }
            if (notification is ScrollEndNotification) {
              _userScrolling = false;
              _scheduleSample();
            }
            return false;
          },
          child: CustomScrollView(
            key: ValueKey(_epoch),
            controller: _scroll,
            center: _center,
            cacheExtent: 200,
            semanticChildCount: _index.chunks.length,
            slivers: [
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _cell(context, _pivot - 1 - i),
                  childCount: _pivot,
                  addAutomaticKeepAlives: false,
                  addSemanticIndexes: false,
                ),
              ),
              SliverList(
                key: _center,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _cell(context, _pivot + i),
                  childCount: _index.chunks.length - _pivot,
                  addAutomaticKeepAlives: false,
                  addSemanticIndexes: false,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: constraints.maxHeight),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Tracked extends SingleChildRenderObjectWidget {
  const _Tracked({
    required this.onAttach,
    required this.onDetach,
    required this.onChanged,
    required super.child,
  });
  final void Function(_TrackedBox) onAttach;
  final void Function(_TrackedBox) onDetach;
  final VoidCallback onChanged;
  @override
  _TrackedBox createRenderObject(BuildContext context) =>
      _TrackedBox(onAttach, onDetach, onChanged);
  @override
  void updateRenderObject(BuildContext context, _TrackedBox renderObject) {
    renderObject.onAttach = onAttach;
    renderObject.onDetach = onDetach;
    renderObject.onChanged = onChanged;
  }
}

class _TrackedBox extends RenderProxyBox {
  _TrackedBox(this.onAttach, this.onDetach, this.onChanged);
  void Function(_TrackedBox) onAttach;
  void Function(_TrackedBox) onDetach;
  VoidCallback onChanged;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    onAttach(this);
  }

  @override
  void detach() {
    onDetach(this);
    super.detach();
  }

  @override
  void performLayout() {
    final old = hasSize ? size : null;
    super.performLayout();
    if (old != null && old != size) onChanged();
  }
}
