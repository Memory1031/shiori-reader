import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'viewport/page_turn.dart';

/// Owns only a visual operation. The book host accepts the terminal commit;
/// both real surfaces stay mounted, including throughout cancellation.
class ReaderCompletionTransition extends StatefulWidget {
  const ReaderCompletionTransition({
    super.key,
    required this.child,
    required this.completion,
    required this.onTurning,
    this.preview,
    this.basis,
    this.canTurn,
    this.onCommit,
    this.animate = true,
    this.style = PageTurnStyle.curl,
  });
  final PageTurnStyle style;
  final Widget child;
  final Widget? completion, preview;
  final Object? basis;
  final bool Function(bool entering)? canTurn;
  final bool Function(bool entering)? onCommit;
  final bool animate;
  final ValueChanged<bool> onTurning;

  @override
  ReaderCompletionTransitionState createState() =>
      ReaderCompletionTransitionState();
}

class ReaderCompletionTransitionState extends State<ReaderCompletionTransition>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(vsync: this);
  late bool _shown = widget.completion != null;
  _CompletionTurn? _operation;
  bool get busy => _operation != null;
  bool _allowed(bool entering) => widget.canTurn?.call(entering) ?? true;
  bool _valid(_CompletionTurn operation) =>
      mounted &&
      identical(operation, _operation) &&
      operation.basis == widget.basis &&
      _allowed(operation.entering);

  void _changed() {
    // Layout/route invalidation can arrive during a parent's build. Retire
    // ownership synchronously, but notify the tree only after that frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onTurning(busy);
          setState(() {});
        }
      });
    } else {
      widget.onTurning(busy);
      setState(() {});
    }
  }

  BoundaryPageDrag? begin(bool entering, double grip) {
    if (busy ||
        entering == _shown ||
        !_allowed(entering) ||
        entering && widget.preview == null) {
      return null;
    }
    final operation = _CompletionTurn(entering, widget.basis, grip);
    _operation = operation;
    _turn.value = 0;
    _changed();
    return BoundaryPageDrag(
      update: (progress) {
        if (_valid(operation) && operation.phase == _Phase.dragging) {
          _turn.value = progress.clamp(0, 1);
        }
      },
      end: (commit) {
        if (!_valid(operation) || operation.phase != _Phase.dragging) return;
        if (commit) {
          unawaited(_settle(operation));
        } else {
          unawaited(cancel());
        }
      },
      cancel: () {
        if (identical(operation, _operation)) unawaited(cancel());
      },
    );
  }

  void turn(bool entering) => begin(entering, pageTurnCentreGrip)?.end(true);

  Future<void> _settle(_CompletionTurn operation) async {
    operation.phase = _Phase.settling;
    try {
      await _animate(1);
    } on TickerCanceled {
      // A cancel owns the rebound; this old continuation must not retire it.
      return;
    }
    if (!_valid(operation) || operation.phase != _Phase.settling) {
      if (identical(operation, _operation) &&
          operation.phase != _Phase.cancelling) {
        await cancel(immediate: true);
      }
      return;
    }
    if (widget.onCommit?.call(operation.entering) ?? false) {
      _shown = operation.entering;
    }
    _operation = null;
    _changed();
  }

  Future<void> _animate(double target) => PaperTurnMotion.settle(
    _turn,
    target: target,
    curve: PageTurnFrame(
      style: widget.style,
      progress: _turn.value,
      direction: 1,
    ).curve,
    reduced:
        !widget.animate ||
        widget.style == PageTurnStyle.none ||
        MediaQuery.disableAnimationsOf(context),
  );

  Future<void> cancel({bool immediate = false}) {
    final operation = _operation;
    if (operation == null) return Future.value();
    if (!immediate && operation.cancellation != null) {
      return operation.cancellation!;
    }
    operation.phase = _Phase.cancelling;
    _turn.stop(canceled: true);
    if (immediate) {
      _operation = null;
      _changed();
      return Future.value();
    }
    return operation.cancellation = _rebound(operation);
  }

  Future<void> _rebound(_CompletionTurn operation) async {
    try {
      await _animate(0);
    } on TickerCanceled {
      return;
    }
    if (!mounted || !identical(_operation, operation)) return;
    _operation = null;
    _changed();
  }

  @override
  void didUpdateWidget(ReaderCompletionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.basis != widget.basis) cancel(immediate: true);
    // Our commit has already reached its endpoint. Parent acknowledgment is
    // not a second navigation request. External navigation is authoritative.
    if ((oldWidget.completion != null) != (widget.completion != null)) {
      cancel(immediate: true);
      _shown = widget.completion != null;
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _turn,
    builder: (context, _) {
      final operation = _operation;
      final entering = operation?.entering ?? _shown;
      final completion = widget.completion ?? widget.preview;
      final paper = Theme.of(context).scaffoldBackgroundColor;
      final frame = PageTurnFrame(
        style: widget.style,
        progress: operation == null ? 1 : _turn.value,
        direction: entering ? 1 : -1,
        grip: operation?.grip ?? pageTurnCentreGrip,
      );
      Widget layer({required bool end, required Widget child}) =>
          Positioned.fill(
            key: ValueKey(
              end ? 'completion-end-layer' : 'completion-reader-layer',
            ),
            child: Offstage(
              offstage: !busy && (end != _shown),
              child: IgnorePointer(
                // The recognizer that accepted a drag stays in the tree and
                // keeps receiving its existing pointer sequence.
                ignoring: busy || end != _shown,
                child: ExcludeFocus(
                  excluding: busy || end != _shown,
                  child: ExcludeSemantics(
                    excluding: busy || end != _shown,
                    child: PageTurnSlot(
                      frame: frame,
                      role: end == entering
                          ? PageTurnRole.entering
                          : PageTurnRole.leaving,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          );
      final reader = layer(end: false, child: widget.child);
      final end = layer(
        end: true,
        child: completion ?? const SizedBox.shrink(),
      );
      final endOnTop = entering ? frame.enteringOnTop : !frame.enteringOnTop;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (!endOnTop) end,
          reader,
          if (busy) PageTurnShade(frame: frame),
          if (endOnTop) end,
          if (busy)
            Positioned.fill(
              child: PageTurnOverlay(frame: frame, paper: paper),
            ),
        ],
      );
    },
  );
}

enum _Phase { dragging, settling, cancelling }

class _CompletionTurn {
  _CompletionTurn(this.entering, this.basis, this.grip);
  final bool entering;
  final Object? basis;
  final double grip;
  _Phase phase = _Phase.dragging;
  Future<void>? cancellation;
}
