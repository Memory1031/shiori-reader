import 'dart:async';

/// Request-scoped metadata, shared by all locator/redirect/body attempts.
/// The application owns the budget; navigation never creates a fresh allowance.
class BackgroundBudget {
  BackgroundBudget({this.maxBytes = 64 * 1024 * 1024, this.maxAttempts = 200});
  final int maxBytes, maxAttempts;
  int bytes = 0, attempts = 0;
  bool get exhausted => bytes >= maxBytes || attempts >= maxAttempts;
  bool attempt() {
    if (exhausted) return false;
    attempts++;
    return true;
  }

  bool receive(int count) {
    bytes += count;
    return bytes <= maxBytes;
  }

  void reset() {
    bytes = 0;
    attempts = 0;
  }
}

class BackgroundWork {
  BackgroundWork(this.budget);
  final BackgroundBudget budget;
  bool promoted = false;
  final onPromoted = <void Function()>{};
  static final _zoneKey = Object();
  static BackgroundWork? get current =>
      Zone.current[_zoneKey] as BackgroundWork?;
  T run<T>(T Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});
  static void promote(BackgroundWork? work) {
    if (current == null && work != null && !work.promoted) {
      work.promoted = true;
      for (final listener in work.onPromoted.toList()) {
        listener();
      }
    }
  }
}
