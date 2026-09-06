import 'package:flutter/widgets.dart';

import '../controllers/scoped_controller.dart';

/// Creates one local controller, without Get registration or service lookup.
/// Use a new key when replacing its dependencies. Keep the builder small.
class ControllerScope<T extends ScopedController> extends StatefulWidget {
  const ControllerScope({
    super.key,
    required this.create,
    required this.builder,
  });

  final T Function() create;
  final Widget Function(BuildContext context, T controller) builder;

  @override
  State<ControllerScope<T>> createState() => _ControllerScopeState<T>();
}

class _ControllerScopeState<T extends ScopedController>
    extends State<ControllerScope<T>> {
  late final T _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.create();
    _controller.onStart();
    _controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.onDelete();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
