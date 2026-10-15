import 'package:flutter/material.dart';
import '../../shared/widgets/shiori_feedback.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'library_controller.dart';
import 'book_batch_views.dart';
import 'book_selection_controller.dart';

/// Single-book entry points share the corresponding destructive confirmation.
Future<bool> removeShelfBook(
  BuildContext context,
  LibraryController controller,
  NovelSummary book,
) async {
  if (controller.writing || controller.isClosed) return false;
  final local = book.key.sourceId == LocalBookIdentity.sourceId;
  final strings = AppLocalizations.of(context);
  if (local) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(strings.localDeleteTitle),
        scrollable: true,
        content: Text(strings.localDeleteMessage(book.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(strings.importCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialog).colorScheme.error,
              foregroundColor: Theme.of(dialog).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(strings.localDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
  } else {
    final route = bookBatchRoute<bool>(
      context,
      (dialog) => BookBatchPanel(
        title: strings.detailRemoveShelf,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.onlineRemoveMessage),
            BookBatchPreview(books: [BookSelectionItem(book.key, book.title)]),
          ],
        ),
        actions: [
          BookBatchAction(
            strings.importCancel,
            () => Navigator.pop(dialog, false),
          ),
          BookBatchAction(
            strings.onlineRemoveConfirm,
            () => Navigator.pop(dialog, true),
            primary: true,
            destructive: true,
          ),
        ],
      ),
    );
    final confirmed = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    if (confirmed != true || !context.mounted) return false;
  }
  final removed = await controller.remove(book.key);
  if (removed && local && context.mounted) {
    ShioriFeedback.show(
      context,
      message: controller.localCleanupPending
          ? strings.localCleanupPending
          : strings.localDeleted,
      kind: controller.localCleanupPending
          ? ShioriFeedbackKind.info
          : ShioriFeedbackKind.success,
    );
  }
  return removed;
}
