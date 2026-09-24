import 'package:flutter/widgets.dart';

import '../../domain/contracts/contracts.dart';
import 'reader_contents.dart';

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

  /// Completion page: back to the last page, leave to the shelf, reread.
  final VoidCallback? completionPrevious, exitToShelf, restart;

  /// Explicit toolbar exit. Unlike system back it never just closes the
  /// toolbars. Defaults to `maybePop`.
  final VoidCallback? leave;
  final VoidCallback? details, prefetch;

  /// Lists the chapter's content links; receives the reader's context so a
  /// footnote can open above the page.
  final void Function(BuildContext readerContext)? links;
  final ValueChanged<LocalContentLink>? contentLink;

  /// The book-level contents layer (volume catalog or local navigation).
  final ReaderContentsLayer Function(BuildContext context)? bookContents;

  bool get hasChapterStepper => previousChapter != null || nextChapter != null;
}
