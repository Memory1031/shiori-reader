import 'package:flutter/foundation.dart';

/// Top-level areas of the desktop management workspace.
enum HomeSection { shelf, search, localBooks, offline, updates }

/// The one owner of the selected [HomeSection].
///
/// Every call is a navigation request and notifies even when the section is
/// unchanged: selecting the current section, or returning to the shelf while
/// it is already selected, still clears the details stacked above its root.
class HomeNavigation extends ChangeNotifier {
  HomeNavigation([this._section = HomeSection.shelf]);

  HomeSection _section;
  HomeSection get section => _section;

  void select(HomeSection section) {
    _section = section;
    notifyListeners();
  }

  void returnToShelf() => select(HomeSection.shelf);
}
