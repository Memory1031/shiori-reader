import 'package:flutter/widgets.dart';

import '../../domain/contracts/contracts.dart';
import 'reader_contents.dart';
import 'reader_panel.dart';

/// Commands a reading surface may invoke, supplied by the screen that owns
/// the book session. A null command hides or disables its control, so one
/// value describes what the toolbar, completion page and gestures can do
/// wherever they are hosted (sheet on phones, side panel on desktop).
@immutable
class ReaderActions {
  const ReaderActions({
    this.previousChapter,
    this.nextChapter,
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
  });

  /// Step to the neighbouring chapter in reading order.
  final VoidCallback? previousChapter, nextChapter;

  /// Forward past the last page of the book's final chapter.
  final VoidCallback? bookEnd;

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

  /// The book-level contents layer (volume catalog or local navigation).
  final ReaderContentsLayer Function(BuildContext context)? bookContents;

  bool get hasChapterStepper => previousChapter != null || nextChapter != null;
}
