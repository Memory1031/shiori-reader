import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../domain/models/models.dart';
import '../../features/statistics/reading_statistics_controller.dart';

class ReadingStatisticsScope extends InheritedWidget {
  const ReadingStatisticsScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final ReadingStatisticsController controller;
  static ReadingStatisticsController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReadingStatisticsScope>()
      ?.controller;
  @override
  bool updateShouldNotify(ReadingStatisticsScope oldWidget) =>
      controller != oldWidget.controller;
}

class ReadingBookScope extends InheritedWidget {
  const ReadingBookScope({super.key, required this.book, required super.child});
  final NovelKey book;
  static NovelKey? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReadingBookScope>()?.book;
  @override
  bool updateShouldNotify(ReadingBookScope oldWidget) => book != oldWidget.book;
}

/// A visible reading surface borrows the app's one recording owner.
class ReadingActivity extends StatefulWidget {
  const ReadingActivity({
    super.key,
    required this.book,
    required this.child,
    this.ready = true,
    this.active = true,
  });
  final NovelKey book;
  final bool ready, active;
  final Widget child;
  @override
  State<ReadingActivity> createState() => _ReadingActivityState();
}

class _ReadingActivityState extends State<ReadingActivity> {
  ReadingStatisticsController? _controller;
  final _owner = Object();
  bool _entered = false;
  int? _resume;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ReadingStatisticsScope.maybeOf(context);
    if (controller != _controller) {
      _controller?.release(_owner);
      _controller = controller;
      _resume = controller?.panelResume;
    }
  }

  @override
  void dispose() {
    _controller?.release(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final child = ReadingBookScope(book: widget.book, child: widget.child);
    if (controller == null) return child;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final visible =
            widget.active &&
            widget.ready &&
            ModalRoute.isCurrentOf(context) != false;
        final entered = visible && !_entered;
        if (visible) _entered = true;
        final resume = visible && _resume != controller.panelResume;
        _resume = controller.panelResume;
        controller.source(
          _owner,
          widget.book,
          visible: visible,
          activity: entered || resume,
        );
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => controller.activity(_owner),
          onPointerMove: (event) {
            if (event.down) controller.activity(_owner);
          },
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) controller.activity(_owner);
          },
          child: Focus(
            skipTraversal: true,
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              controller.activity(_owner);
              return KeyEventResult.ignored;
            },
            child: child,
          ),
        );
      },
    );
  }
}

/// Popups closed by the user are continuation; retired routes aren't.
class ReadingStatisticsObserver extends NavigatorObserver {
  ReadingStatisticsObserver(this.controller);
  final ReadingStatisticsController controller;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => controller.panelClosed(),
      );
    }
  }
}
