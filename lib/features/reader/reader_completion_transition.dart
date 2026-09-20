import 'package:flutter/material.dart';
import 'viewport/paper_turn.dart';

/// Keeps the real last page mounted while revealing or leaving reader chrome.
class ReaderCompletionTransition extends StatefulWidget {
  const ReaderCompletionTransition({
    super.key,
    required this.child,
    required this.completion,
    required this.onTurning,
  });
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
    if (_reduced) {
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
      await PaperTurnMotion.settle(_turn);
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
      final reader = Positioned.fill(
        key: const ValueKey('completion-reader-layer'),
        child: IgnorePointer(
          ignoring: entering || _turn.isAnimating,
          child: ExcludeSemantics(
            excluding: entering,
            child: ClipPath(
              clipper: entering ? PaperTurnClipper(_turn.value, 1) : null,
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
            child: ClipPath(
              clipper: PaperTurnClipper(entering ? 0 : _turn.value, -1),
              child: completion,
            ),
          ),
        ),
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          if (entering && completion != null) end,
          reader,
          if (!entering && completion != null) end,
          if (_turn.isAnimating)
            Positioned.fill(
              child: PaperTurnFold(
                progress: _turn.value,
                direction: entering ? 1 : -1,
                paper: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
        ],
      );
    },
  );
}
