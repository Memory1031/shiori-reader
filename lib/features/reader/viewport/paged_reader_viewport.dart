import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import '../../../domain/models/models.dart';
import 'page_layout.dart';
import 'page_boundaries.dart';
import 'render_chunk.dart';
import 'block_style.dart';
import 'reader_box.dart';
import 'page_turn.dart';
import '../reader_linked_text.dart';
import '../reader_tap_zones.dart';
import '../reader_margin.dart';
import '../../../domain/contracts/contracts.dart';

class PagedReaderController {
  _PagedReaderViewportState? _state;
  ReaderPosition? capture() => _state?._position;
  void restore(ReaderPosition position) => _state?._restore(position);
  Future<void> next({bool queueIfTurning = false}) =>
      _state?._turn(1, queueIfTurning: queueIfTurning) ?? Future.value();
  Future<void> previous({bool queueIfTurning = false}) =>
      _state?._turn(-1, queueIfTurning: queueIfTurning) ?? Future.value();

  /// Keep the already visible last page anchored to the canonical end on
  /// later geometry changes, without replacing or restoring the current page.
  void anchorAtEnd() {
    if (_state case final state?) state._anchorAtEnd = true;
  }

  int get measuredChunks => _state?._layout?.measuredChunks ?? 0;
  int get layoutGeneration => _state?._epoch ?? 0;
  int get cachedPages => _state?._pages.length ?? 0;
  bool get usedFallback => _state?._usedFallback ?? false;
  bool get isRestoring => _state?._restoring ?? false;
}

/// Hosts the viewport's existing horizontal gesture on the reader surface,
/// independently of the text's layout bounds. Taps remain in the viewport.
class PagedReaderDragSurface extends StatefulWidget {
  const PagedReaderDragSurface({
    super.key,
    required this.controller,
    required this.enabled,
    required this.isCurrent,
    required this.pageSize,
    required this.pageOrigin,
    required this.child,
  });
  final PagedReaderController controller;
  final bool enabled;
  final bool Function() isCurrent;
  final Size pageSize;
  // The surface is inside SafeArea; folds use the full Reader page coordinates.
  final Offset pageOrigin;
  final Widget child;

  @override
  State<PagedReaderDragSurface> createState() => PagedReaderDragSurfaceState();
}

class PagedReaderDragSurfaceState extends State<PagedReaderDragSurface> {
  _PagedReaderViewportState? _owner;
  int? _epoch, _pointer;
  int? _movingPointer;
  final _contributingPointers = <int>{};
  bool get _owns =>
      _owner != null &&
      identical(widget.controller._state, _owner) &&
      _owner!.mounted &&
      _owner!._epoch == _epoch &&
      _owner!._gestureAccepted;

  void cancel() {
    final owner = _owner;
    _owner = null;
    _epoch = null;
    _pointer = null;
    _movingPointer = null;
    _contributingPointers.clear();
    if (owner == null) return;
    if (owner.mounted) owner._dragCancel();
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(PagedReaderDragSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Disabling new input while a chapter/completion target prepares must not
    // remove an accepted recognizer. Geometry/ownership changes do retire it.
    if (oldWidget.controller != widget.controller ||
        oldWidget.pageSize != widget.pageSize ||
        oldWidget.pageOrigin != widget.pageOrigin ||
        !widget.isCurrent()) {
      cancel();
    }
  }

  @override
  void dispose() {
    if (_owns) _owner!._dragCancel();
    _owner = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listening = widget.enabled || _owner != null;
    return Listener(
      onPointerDown: (event) {
        if (_pointer == null &&
            widget.enabled &&
            event.buttons == kPrimaryButton) {
          _pointer = event.pointer;
        }
      },
      onPointerUp: (event) {
        if (_pointer == event.pointer) _pointer = null;
      },
      // Hit-test listeners run before recognizer routes. Only an actual drag
      // update below records this pointer as contributing to the turn.
      onPointerMove: (event) => _movingPointer = event.pointer,
      onPointerPanZoomUpdate: (event) => _movingPointer = event.pointer,
      // An accepted Flutter drag can report PointerCancel as end. Retire the
      // turn before that callback if a starting or contributing pointer cancels.
      onPointerCancel: (event) {
        // After the first finger lifts, Flutter can keep the drag owned by a
        // remaining finger. Its final cancellation must not become a commit.
        if (_pointer == event.pointer ||
            _contributingPointers.contains(event.pointer) ||
            _pointer == null && _owner != null) {
          cancel();
        }
      },
      child: IgnorePointer(
        // Hit paths of accepted pointers stay alive. New pointers must not
        // enter the recognizer while the host is preparing another surface.
        ignoring: !widget.enabled,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          gestures: {
            if (listening)
              HorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer
                  >(
                    () => HorizontalDragGestureRecognizer(debugOwner: this),
                    (recognizer) => recognizer
                      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(
                        context,
                      )
                      ..multitouchDragStrategy = ScrollConfiguration.of(
                        context,
                      ).getMultitouchDragStrategy(context)
                      // Blank has no tap competitor to delay arena acceptance.
                      // Use Flutter's ordinary drag slop for both blank and text.
                      ..onlyAcceptDragOnThreshold = true
                      ..onStart = (details) {
                        if (!widget.enabled || !widget.isCurrent()) return;
                        final state = widget.controller._state;
                        if (state == null ||
                            !state.widget.hostedDrag ||
                            !state._dragStart(
                              details.localPosition.dy + widget.pageOrigin.dy,
                            )) {
                          return;
                        }
                        setState(() {
                          _owner = state;
                          _epoch = state._epoch;
                          _contributingPointers.clear();
                        });
                      }
                      ..onUpdate = (details) {
                        if (!_owns || !widget.isCurrent()) {
                          cancel();
                          return;
                        }
                        if (details.delta.dx != 0 && _movingPointer != null) {
                          _contributingPointers.add(_movingPointer!);
                        }
                        _owner!._dragUpdate(details);
                      }
                      ..onEnd = (details) {
                        if (!_owns || !widget.isCurrent()) {
                          cancel();
                          return;
                        }
                        final owner = _owner!;
                        setState(() {
                          _owner = null;
                          _epoch = null;
                          _pointer = null;
                          _movingPointer = null;
                          _contributingPointers.clear();
                        });
                        owner._dragEnd(details);
                      }
                      ..onCancel = cancel,
                  ),
          },
          child: widget.child,
        ),
      ),
    );
  }
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
    this.chromeVisible,
    this.onBoundary,
    this.onBoundaryDrag,
    this.onEdges,
    this.inputEnabled = true,
    this.hostedDrag = false,
    this.onTurning,
    this.onTurnVisual,
    this.pageSize,
    this.contentOrigin = Offset.zero,
    this.startAtEnd = false,
    this.contentLinks = const [],
    this.onLink,
    this.onFootnote,
    this.images,
    this.columns = 1,
    this.columnGap = readerColumnGap,
    this.turnStyle = PageTurnStyle.curl,
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

  /// While true, taps dismiss the reader chrome instead of turning pages.
  final ValueListenable<bool>? chromeVisible;
  final ValueChanged<int>? onBoundary;
  final BoundaryPageDrag? Function(int direction, double grip)? onBoundaryDrag;
  final void Function(bool first, bool last)? onEdges;
  final bool inputEnabled;

  /// The Reader hosts horizontal input outside its content padding. Standalone
  /// viewports retain their own recognizer; the two modes are mutually exclusive.
  final bool hostedDrag;
  final ValueChanged<bool>? onTurning;

  /// Reports each frame of a turn so the host can paint the curl over the
  /// full reader page; when null the viewport paints it itself.
  final ValueChanged<PageTurnFrame>? onTurnVisual;
  final PageTurnStyle turnStyle;
  final Size? pageSize;
  final Offset contentOrigin;
  final bool startAtEnd;
  final List<LocalContentLink> contentLinks;
  final ValueChanged<LocalContentLink>? onLink;

  /// Shows a footnote tapped in the text; the text's own sheet when null.
  final ValueChanged<LocalContentLink>? onFootnote;
  @override
  State<PagedReaderViewport> createState() => _PagedReaderViewportState();
}

class _PagedReaderViewportState extends State<PagedReaderViewport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turnAnimation;
  int _current = 0;
  int? _target;
  int? _queuedDirection;
  bool _acceptsQueuedTurn = false;
  int _direction = 1;
  double _grip = pageTurnCentreGrip;
  PageTurnFrame get _frame => PageTurnFrame(
    style: widget.turnStyle,
    progress: _turnAnimation.value,
    direction: _direction,
    grip: _grip,
  );
  double _dragDistance = 0;
  int? _dragDirection;
  BoundaryPageDrag? _boundaryDrag;
  bool _gestureAccepted = false;
  bool get _acceptsDrag => widget.inputEnabled || _gestureAccepted;
  double get _dragProgress =>
      (-_dragDistance *
              (_dragDirection ?? 1) /
              (widget.pageSize?.width ?? _layout?.width ?? 360))
          .clamp(0.0, 1.0);
  final _pages = <int, ReaderPage>{};
  // Only mounted illustration owners: reflow can move an image between
  // columns without releasing its lease and immediately requesting it again.
  final _imageKeys = <String, GlobalKey>{};
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
    _turnAnimation = AnimationController(
      vsync: this,
      duration: PaperTurnMotion.duration,
    )..addListener(_reportTurn);
    _attach();
    _position = widget.initialPosition;
    _anchorAtEnd = widget.startAtEnd;
  }

  bool _visualQueued = false;
  void _reportTurn() {
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_visualQueued) return;
      _visualQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _visualQueued = false;
        if (mounted) widget.onTurnVisual?.call(_frame);
      });
    } else {
      widget.onTurnVisual?.call(_frame);
    }
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
    if (oldWidget.content != widget.content) _imageKeys.clear();
    if (oldWidget.onEdges == null && widget.onEdges != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sample();
      });
    }
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
    _queuedDirection = null;
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
        reduced: reduced || !_frame.animates,
        curve: _frame.curve,
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
    if (!commit) _queuedDirection = null;
    if (_queuedDirection != null) {
      // Let pending layout/route changes settle before consuming the one-slot
      // input buffer. Explicit restores and new gestures invalidate it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _epoch) return;
        final direction = _queuedDirection;
        _queuedDirection = null;
        if (direction == null ||
            _restoring ||
            _target != null ||
            ModalRoute.of(context)?.isCurrent == false ||
            (WidgetsBinding.instance.lifecycleState != null &&
                WidgetsBinding.instance.lifecycleState !=
                    AppLifecycleState.resumed)) {
          return;
        }
        _turn(direction, queueIfTurning: true);
      });
    }
  }

  Future<void> _turn(int direction, {bool queueIfTurning = false}) async {
    if (!widget.inputEnabled ||
        _boundaryDrag != null ||
        _layout == null ||
        _restoring) {
      return;
    }
    if (_target != null) {
      if (queueIfTurning && _acceptsQueuedTurn) {
        // Repeated input coalesces; reversing intent drops the pending turn
        // without interrupting the page already moving.
        _queuedDirection = direction == _direction ? direction : null;
      }
      return;
    }
    _queuedDirection = null;
    if (_page(_current + direction) == null) {
      widget.onBoundary?.call(direction);
      return;
    }
    // Taps and keys have no held point; turn from the page centre.
    _grip = pageTurnCentreGrip;
    setState(() {
      _acceptsQueuedTurn = queueIfTurning;
      _direction = direction;
      _target = _current + direction;
      _userScrolling = true;
    });
    widget.onTurning?.call(true);
    await _finish(true);
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_gestureAccepted ||
        _layout == null ||
        _restoring ||
        _turnAnimation.isAnimating) {
      return;
    }
    _dragDistance += details.delta.dx;
    _dragDirection ??= _dragDistance < 0 ? 1 : -1;
    final direction = _dragDirection!;
    if (_target == null && _boundaryDrag == null) {
      if (_page(_current + direction) == null) {
        _boundaryDrag = widget.onBoundaryDrag?.call(direction, _grip);
      } else {
        setState(() {
          _acceptsQueuedTurn = false;
          _direction = direction;
          _target = _current + direction;
          _userScrolling = true;
        });
        widget.onTurning?.call(true);
      }
    }
    if (_boundaryDrag case final drag?) {
      drag.update(_dragProgress);
    } else if (_target != null) {
      _turnAnimation.value = _dragProgress;
    }
  }

  bool _dragStart(double pageY) {
    if (!widget.inputEnabled ||
        _turnAnimation.isAnimating ||
        _target != null ||
        _gestureAccepted ||
        _restoring ||
        _layout == null) {
      return false;
    }
    _gestureAccepted = true;
    _queuedDirection = null;
    _dragDirection = null;
    _boundaryDrag = null;
    _dragDistance = 0;
    _grip = pageTurnGrip(pageY, widget.pageSize?.height ?? _layout!.height);
    return true;
  }

  void _dragEnd(DragEndDetails details) {
    if (!_gestureAccepted || _turnAnimation.isAnimating) return;
    _gestureAccepted = false;
    final direction = _dragDirection;
    final commit = pageTurnCommits(
      _dragProgress,
      -(details.primaryVelocity ?? 0) * (direction ?? 1),
    );
    if (_boundaryDrag case final drag?) {
      _boundaryDrag = null;
      drag.end(commit);
    } else if (_target != null) {
      _finish(commit);
    } else if (direction != null && commit) {
      widget.onBoundary?.call(direction);
    }
    _dragDistance = 0;
    _dragDirection = null;
  }

  BoundaryPageDrag? _retireGesture() {
    _gestureAccepted = false;
    _dragDistance = 0;
    _dragDirection = null;
    final drag = _boundaryDrag;
    _boundaryDrag = null;
    return drag;
  }

  void _dragCancel() {
    final drag = _retireGesture();
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => drag?.cancel());
    } else {
      drag?.cancel();
    }
    if (_target != null && !_turnAnimation.isAnimating) _finish(false);
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
    widget.onEdges?.call(
      PageBoundaries.compare(page.start, const PageCursor(0, 0)) == 0,
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
        textStyle.copyWith(
          color: Colors.black,
          backgroundColor: Colors.transparent,
        ),
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
        // A seek may remove the recognizer before it receives end/cancel.
        // Retire its handle now; notify the host outside layout so cancellation
        // can safely rebuild ancestors. Repeated retirement is a no-op.
        if (_retireGesture() case final drag?) {
          WidgetsBinding.instance.addPostFrameCallback((_) => drag.cancel());
        }
        _queuedDirection = null;
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
        final wasTurning = _target != null;
        _turnAnimation.stop(canceled: true);
        _turnAnimation.value = 0;
        _target = null;
        _userScrolling = false;
        if (wasTurning) widget.onTurning?.call(false);
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
      double fragmentInnerWidth(PageFragment f) => readerBoxInnerWidth(
        fragmentBlock(f),
        columnWidth,
        style: textStyle,
        scaler: scaler,
      );
      Widget frameFragment(PageFragment f, double width, Widget child) {
        final chunk = _layout!.index.chunks[f.unit], block = fragmentBlock(f);
        final boxes = readerBlockBoxes(
          block,
          width,
          textStyle,
          scaler,
          pageHeight: constraints.maxHeight,
          minimumContentHeight: f.boxContentHeight,
        );
        final edges = readerBoxEdges(
          widget.content,
          chunk.blockIndex,
          width: width,
          style: textStyle,
          scaler: scaler,
          pageHeight: constraints.maxHeight,
          minimumContentHeight: f.boxContentHeight,
        );
        final starts = chunk.start + f.start == 0;
        final ends =
            chunk.text == null ||
            chunk.text!.isEmpty ||
            chunk.start + f.end == chunk.total;
        final outerTop = starts ? edges.outerTop.clamp(0.0, f.boxTop) : 0.0;
        final outerBottom = ends
            ? edges.outerBottom.clamp(0.0, f.boxBottom)
            : 0.0;
        final local = ReaderBoxFrame(
          box: block.layout,
          width: boxes.local?.width ?? boxes.innerWidth,
          geometry: boxes.local,
          top: f.boxTop - outerTop,
          bottom: f.boxBottom - outerBottom,
          starts: starts,
          ends: ends,
          child: child,
        );
        return ReaderBoxFrame(
          box: block.box,
          linkOwnsDecoration:
              f.linkLayout != null &&
              block is ParagraphBlock &&
              block.linkDecoration?.onBlock == true,
          width: boxes.outer?.width ?? width,
          geometry: boxes.outer,
          top: outerTop,
          bottom: outerBottom,
          starts:
              starts &&
              (chunk.blockIndex == 0 ||
                  widget.content.blocks[chunk.blockIndex - 1].box?.group !=
                      block.box?.group),
          ends:
              ends &&
              (chunk.blockIndex + 1 == widget.content.blocks.length ||
                  widget.content.blocks[chunk.blockIndex + 1].box?.group !=
                      block.box?.group),
          child: local,
        );
      }

      Widget? buildPage(BuildContext context, int number) {
        final page = _page(number);
        if (page == null) return null;
        Widget column(
          List<PageFragment> fragments,
          double width, {
          bool centered = false,
        }) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          // Centered pages shrink-wrap so Align can place them mid-page;
          // top-aligned pages keep the column filling for stable hit tests.
          mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
          children: [
            for (final fragment in fragments)
              Semantics(
                header:
                    widget.content.blocks[_layout!
                            .index
                            .chunks[fragment.unit]
                            .blockIndex]
                        is HeadingBlock,
                child: frameFragment(
                  fragment,
                  width,
                  SizedBox(
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
                                    pageHeight: constraints.maxHeight,
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
                                    pageHeight: constraints.maxHeight,
                                    chapter: widget.content.key,
                                  ) /
                                  2,
                            ),
                            child: ReaderLinkedText(
                              decoration: fragment.linkLayout == null
                                  ? null
                                  : (fragmentBlock(fragment) as ParagraphBlock)
                                        .linkDecoration,
                              linkLayout: fragment.linkLayout,
                              flow: fragment.flow,
                              readerFontSize: textStyle.fontSize,
                              locale: locale,
                              textHeightBehavior: heightBehavior,
                              images: widget.images,
                              authoredBackground: fragmentBlock(
                                fragment,
                              ).box?.backgroundColor,
                              inlineRuby: fragmentBlock(fragment).inlineRuby,
                              inlineStacks: _layout!.inlineStacks(
                                fragmentBlock(fragment),
                              ),
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
                              onFootnote: widget.onFootnote,
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
        Widget spreadColumn(List<PageFragment> fragments) {
          final centered = _layout!.isIllustrationColumn(fragments);
          return Align(
            alignment: centered ? Alignment.center : Alignment.topCenter,
            child: column(fragments, columnWidth, centered: centered),
          );
        }

        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: widget.columns == 1 || page.fullWidth
              ? Align(
                  alignment: page.centered
                      ? Alignment.center
                      : Alignment.topCenter,
                  child: SizedBox(
                    width: page.fullWidth
                        ? constraints.maxWidth.clamp(0, readerMaxPageWidth)
                        : constraints.maxWidth,
                    child: column(
                      page.fragments,
                      page.fullWidth
                          ? constraints.maxWidth.clamp(0, readerMaxPageWidth)
                          : constraints.maxWidth,
                      centered: page.centered,
                    ),
                  ),
                )
              : Row(
                  textDirection: TextDirection.ltr,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: spreadColumn(
                        page.fragments
                            .take(page.columnBreak ?? page.fragments.length)
                            .toList(),
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
                      child: spreadColumn(
                        page.columnBreak == null
                            ? []
                            : page.fragments.skip(page.columnBreak!).toList(),
                      ),
                    ),
                  ],
                ),
        );
      }

      _lastReadyPage = buildPage(context, _current);
      // Built once per turn: _target only changes through setState, so the
      // animation frames reuse it instead of re-measuring every fragment.
      final targetPage = _target == null ? null : buildPage(context, _target!);
      final visibleBlocks = <String>{
        for (final number in [_current, ?_target])
          for (final fragment in _pages[number]?.fragments ?? <PageFragment>[])
            if (fragmentBlock(fragment) case ImageBlock(:final blockKey))
              blockKey,
      };
      _imageKeys.removeWhere((key, _) => !visibleBlocks.contains(key));
      _seekPreview = null;
      return Semantics(
        key: const ValueKey('paper-reader-pages'),
        container: true,
        onScrollLeft: () => _turn(1),
        onScrollRight: () => _turn(-1),
        child: Listener(
          // Flutter's accepted drag recognizer reports PointerCancel as end.
          // This local listener only cancels our already owned gesture.
          onPointerCancel: widget.hostedDrag ? null : (_) => _dragCancel(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: widget.hostedDrag || !_acceptsDrag
                ? null
                : (details) {
                    _dragStart(
                      details.localPosition.dy + widget.contentOrigin.dy,
                    );
                  },
            onHorizontalDragUpdate: !widget.hostedDrag && _acceptsDrag
                ? _dragUpdate
                : null,
            onHorizontalDragEnd: !widget.hostedDrag && _acceptsDrag
                ? _dragEnd
                : null,
            onHorizontalDragCancel: !widget.hostedDrag && _acceptsDrag
                ? _dragCancel
                : null,
            onTapUp: (details) {
              if (!widget.inputEnabled) return;
              switch (readerTapZone(
                details.localPosition.dx,
                constraints.maxWidth,
                chromeVisible: widget.chromeVisible?.value ?? false,
              )) {
                case ReaderTap.previous:
                  _turn(-1, queueIfTurning: true);
                case ReaderTap.next:
                  _turn(1, queueIfTurning: true);
                case ReaderTap.center:
                  _queuedDirection = null;
                  widget.onCenterTap?.call();
              }
            },
            child: AnimatedBuilder(
              animation: _turnAnimation,
              builder: (context, _) {
                final frame = _frame;
                final paper = Theme.of(context).scaffoldBackgroundColor;
                Widget slot(int number) => ExcludeSemantics(
                  key: ValueKey((widget.content.key, number)),
                  excluding: number != _current,
                  child: PageTurnSlot(
                    frame: frame,
                    role: number == _current
                        ? PageTurnRole.leaving
                        : PageTurnRole.entering,
                    paper: paper,
                    pageSize: widget.pageSize,
                    contentOrigin: widget.contentOrigin,
                    child: number == _current ? _lastReadyPage! : targetPage!,
                  ),
                );
                final target = _target;
                final lower = target != null && frame.enteringOnTop
                    ? _current
                    : target;
                final upper = target != null && frame.enteringOnTop
                    ? target
                    : _current;
                return ClipRect(
                  clipper: _PageBoundsClip(
                    widget.pageSize,
                    widget.contentOrigin,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (lower != null) slot(lower),
                      if (target != null)
                        PageTurnShade(frame: frame, pageSize: widget.pageSize),
                      slot(upper),
                      if (widget.onTurnVisual == null)
                        PageTurnOverlay(frame: frame, paper: paper),
                    ],
                  ),
                );
              },
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
      return KeyedSubtree(
        key: _imageKeys.putIfAbsent(block.blockKey, GlobalKey.new),
        child:
            widget.imageBuilder?.call(context, block) ??
            Center(child: Text(block.alt ?? '')),
      );
    }
    return const Divider();
  }
}

/// Clips a turn to the full reader page width rather than the text column,
/// so a sliding sheet travels through the margins instead of appearing at
/// the column edge.
class _PageBoundsClip extends CustomClipper<Rect> {
  const _PageBoundsClip(this.pageSize, this.origin);
  final Size? pageSize;
  final Offset origin;
  @override
  Rect getClip(Size size) => switch (pageSize) {
    final page? => Rect.fromLTWH(-origin.dx, 0, page.width, size.height),
    null => Offset.zero & size,
  };

  @override
  bool shouldReclip(_PageBoundsClip old) =>
      old.pageSize != pageSize || old.origin != origin;
}
