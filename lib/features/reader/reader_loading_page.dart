import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../shared/widgets/state_views.dart';

/// Keep the loading geometry independent of system bars and reader toolbars.
class ReaderLoadingPage extends StatelessWidget {
  const ReaderLoadingPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const LoadingView(),
        if (Navigator.of(context).canPop())
          const Positioned(
            top: 0,
            left: 0,
            child: SafeArea(child: BackButton()),
          ),
      ],
    ),
  );
}

/// The page stays mounted and lays out beneath the paper until restoration ends.
class ReaderOpeningTransition extends StatelessWidget {
  const ReaderOpeningTransition({
    super.key,
    required this.ready,
    required this.child,
  });

  final ValueListenable<bool> ready;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ready,
    child: child,
    builder: (context, ready, child) => Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: !ready,
          child: ExcludeFocus(
            excluding: !ready,
            child: ExcludeSemantics(excluding: !ready, child: child!),
          ),
        ),
        IgnorePointer(
          ignoring: ready,
          child: ExcludeSemantics(
            excluding: ready,
            child: AnimatedOpacity(
              opacity: ready ? 0 : 1,
              duration: ShioriMotion.of(context, ShioriMotion.feedback),
              curve: Curves.easeOut,
              child: ready
                  ? ColoredBox(color: Theme.of(context).scaffoldBackgroundColor)
                  : const ReaderLoadingPage(),
            ),
          ),
        ),
      ],
    ),
  );
}
