import 'dart:async';

import 'package:get/get_state_manager/get_state_manager.dart';

import '../../domain/contracts/cancellation.dart';

/// Owned by one ControllerScope. Shared repositories are borrowed, not owned.
abstract class ScopedController extends GetxController {
  final _lifetime = CancellationSource();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Future<void> _resourcesReleased = Future<void>.value();

  CancellationToken get cancellation => _lifetime.token;
  Future<void> get resourcesReleased => _resourcesReleased;

  /// Subscribe before loading. Late stream events cannot reach a closed scope.
  void listenTo<T>(Stream<T> stream, void Function(T) onData) {
    if (isClosed) throw StateError('Controller is closed');
    _subscriptions.add(
      stream.listen((value) {
        if (!isClosed) onData(value);
      }),
    );
  }

  @override
  void onClose() {
    _lifetime.cancel();
    _resourcesReleased = Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    _subscriptions.clear();
    super.onClose();
  }
}
