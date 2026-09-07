import 'package:flutter/widgets.dart';
import 'library_controller.dart';

/// Observes a borrowed controller without taking over its lifetime.
class LibraryObserver extends StatefulWidget {
  const LibraryObserver({
    super.key,
    required this.controller,
    required this.builder,
  });
  final LibraryController controller;
  final Widget Function(BuildContext, LibraryController) builder;
  @override
  State<LibraryObserver> createState() => _LibraryObserverState();
}

class _LibraryObserverState extends State<LibraryObserver> {
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(LibraryObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (!oldWidget.controller.isClosed) {
        oldWidget.controller.removeListener(_changed);
      }
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    if (!widget.controller.isClosed) widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.controller);
}
