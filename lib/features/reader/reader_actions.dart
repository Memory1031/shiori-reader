import 'package:flutter/widgets.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import 'reader_contents.dart';
import 'reader_panel.dart';

/// Commands a reading surface may invoke, supplied by the screen that owns
/// the book session. A null command hides or disables its control, so one
/// value describes what the toolbar, completion page and gestures can do
/// wherever they are hosted (sheet on phones, side panel on desktop).
@immutable
class ReaderActions {
  const ReaderActions({
    this.toggleBookmark,
    this.showBookmarks,
    this.isBookmarked,
    this.bookmarkSupported = true,
    this.previousChapter,
    this.nextChapter,
    this.navigateChapter,
    this.bookEnd,
    this.completionPrevious,
    this.exitToShelf,
    this.restart,
    this.leave,
    this.details,
    this.prefetch,
    this.links,
    this.contentLink,
    this.bookContents,
    this.previousLocation,
    this.navigatePosition,
    this.pageTurnCommitted,
    this.previousLocationLabel,
  });

  final VoidCallback? toggleBookmark;
  final void Function(BuildContext)? showBookmarks;
  final bool Function()? isBookmarked;
  final bool bookmarkSupported;

  /// Turn to the neighbouring chapter at a page boundary.
  final VoidCallback? previousChapter, nextChapter;

  /// Progress-panel chapter navigation; preserves reading controls. When
  /// absent, the surface uses the corresponding chapter step above.
  final ValueChanged<int>? navigateChapter;

  /// Commit completion after revalidating the book's final chapter. False
  /// means the host rejected a stale request; the text must stay visible.
  final bool Function()? bookEnd;

  /// Completion page: return to the text (also used before an in-chapter
  /// jump from the completion page), leave to the shelf, reread.
  final VoidCallback? completionPrevious, exitToShelf, restart;

  /// Explicit toolbar exit. Unlike system back it never just closes the
  /// toolbars. Defaults to `maybePop`.
  final VoidCallback? leave;
  final VoidCallback? details;

  /// Prefetch settings and progress, opened in the page's panel slot.
  final void Function(ReaderPanels panels)? prefetch;

  /// Lists the chapter's content links in the page's panel slot, from which
  /// a footnote opens over the page too.
  final void Function(ReaderPanels panels)? links;
  final ValueChanged<LocalContentLink>? contentLink;
  final VoidCallback? previousLocation, pageTurnCommitted;
  final String? previousLocationLabel;

  /// Explicit position selection; the predicate stays bound to its page/panel.
  final Future<void> Function(ReaderPosition, bool Function())?
  navigatePosition;

  /// The book-level contents layer (volume catalog or local navigation).
  final ReaderContentsLayer Function(BuildContext context)? bookContents;

  bool get hasChapterStepper => previousChapter != null || nextChapter != null;
}
