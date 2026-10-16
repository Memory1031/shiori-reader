import 'package:flutter/widgets.dart';
import '../../domain/contracts/user_bookmarks.dart';

/// App-owned user data, explicitly provided above Reader routes.
class UserBookmarkScope extends InheritedWidget {
  const UserBookmarkScope({
    super.key,
    required this.repository,
    required super.child,
  });
  final UserBookmarkRepository repository;
  static UserBookmarkRepository? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<UserBookmarkScope>()
      ?.repository;
  @override
  bool updateShouldNotify(UserBookmarkScope oldWidget) =>
      repository != oldWidget.repository;
}
