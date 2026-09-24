import 'package:flutter/material.dart';
import 'viewport/page_turn.dart';

/// Keeps the real last page mounted while revealing or leaving reader chrome.
class ReaderCompletionTransition extends StatefulWidget {
  const ReaderCompletionTransition({
    super.key,
    required this.child,
    required this.completion,
    required this.onTurning,
    this.style = PageTurnStyle.curl,
  });
  final PageTurnStyle style;
  final Widget child;
  final Widget? completion;
  final ValueChanged<bool> onTurning;

  @override
  State<ReaderCompletionTransition> createState() =>
      _ReaderCompletionTransitionState();
}

class _ReaderCompletionTransitionState extends State<ReaderCompletionTransition>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(vsync: this, value: 1);
  Widget? _outgoing;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced && _turn.isAnimating) _turn.value = 1;
  }

  @override
  void initState() {
    super.initState();
    _turn.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onTurning(false);
        if (_outgoing != null) setState(() => _outgoing = null);
      }
    });
  }

  @override
  void didUpdateWidget(ReaderCompletionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.completion == null) == (widget.completion == null)) return;
    _outgoing = widget.completion == null ? oldWidget.completion : null;
    if (_reduced || widget.style == PageTurnStyle.none) {
      _outgoing = null;
      _turn.value = 1;
      widget.onTurning(false);
      return;
    }
    widget.onTurning(true);
    _turn.value = 0;
    _animate();
  }

  Future<void> _animate() async {
    try {
      await PaperTurnMotion.settle(
        _turn,
        curve: PageTurnFrame(
          style: widget.style,
          progress: 0,
          direction: 1,
        ).curve,
      );
    } on TickerCanceled {
      // Replacement/disposal owns the next visual state.
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
      final entering = widget.completion != null;
      final completion = widget.completion ?? _outgoing;
      final paper = Theme.of(context).scaffoldBackgroundColor;
      // Entering the completion page turns forward away from the reader;
      // leaving it turns back, so the completion page is the one leaving.
      final frame = PageTurnFrame(
        style: widget.style,
        progress: _turn.value,
        direction: entering ? 1 : -1,
      );
      final reader = Positioned.fill(
        key: const ValueKey('completion-reader-layer'),
        child: IgnorePointer(
          ignoring: entering || _turn.isAnimating,
          child: ExcludeSemantics(
            excluding: entering,
            child: PageTurnSlot(
              frame: frame,
              role: entering ? PageTurnRole.leaving : PageTurnRole.entering,
              child: widget.child,
            ),
          ),
        ),
      );
      final end = Positioned.fill(
        key: const ValueKey('completion-end-layer'),
        child: IgnorePointer(
          ignoring: _turn.isAnimating || !entering,
          child: ExcludeSemantics(
            excluding: !entering,
            child: PageTurnSlot(
              frame: frame,
              role: entering ? PageTurnRole.entering : PageTurnRole.leaving,
              child: completion ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
      // Leaving above entering, except a forward cover slides in on top.
      final endOnTop = entering ? frame.enteringOnTop : !frame.enteringOnTop;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (!endOnTop && completion != null) end,
          reader,
          if (_turn.isAnimating) PageTurnShade(frame: frame),
          if (endOnTop && completion != null) end,
          if (_turn.isAnimating)
            Positioned.fill(
              child: PageTurnOverlay(frame: frame, paper: paper),
            ),
        ],
      );
    },
  );
}
