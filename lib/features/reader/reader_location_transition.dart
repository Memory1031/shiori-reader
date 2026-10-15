import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';

/// A confirmed change of page briefly reveals the live target; never the wait.
class ReaderLocationTransition extends StatefulWidget {
  const ReaderLocationTransition({
    super.key,
    required this.revision,
    required this.enabled,
    required this.paper,
    required this.child,
  });
  final int revision;
  final bool enabled;
  final Color paper;
  final Widget child;
  @override
  State<ReaderLocationTransition> createState() =>
      _ReaderLocationTransitionState();
}

class _ReaderLocationTransitionState extends State<ReaderLocationTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    value: 1,
    duration: ShioriMotion.feedback,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _motion.value = 1;
    }
  }

  @override
  void didUpdateWidget(ReaderLocationTransition old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) {
      _motion.value = 1;
    } else if (widget.revision != old.revision) {
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: widget.paper,
    child: AnimatedBuilder(
      animation: _motion,
      child: widget.child,
      builder: (context, child) {
        final remaining = 1 - Curves.easeOut.transform(_motion.value);
        return Transform.translate(
          offset: Offset(8 * remaining, 0),
          child: Opacity(opacity: 1 - .12 * remaining, child: child),
        );
      },
    ),
  );
}
