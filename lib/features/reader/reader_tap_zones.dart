/// Where a tap lands on a reading surface.
enum ReaderTap { previous, center, next }

/// Shared page-turn zones for native, EPUB and completion pages: the outer
/// 30% on each side turns, the middle toggles chrome. [width] is the tapped
/// surface's own width, so a docked side panel never skews the zones. While
/// [chromeVisible], every tap only dismisses the chrome.
ReaderTap readerTapZone(double dx, double width, {bool chromeVisible = false}) {
  if (chromeVisible) return ReaderTap.center;
  if (dx < width * .3) return ReaderTap.previous;
  if (dx > width * .7) return ReaderTap.next;
  return ReaderTap.center;
}
