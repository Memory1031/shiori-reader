import 'package:flutter/material.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'library_controller.dart';

/// All shelf removal entry points share the local-file deletion confirmation.
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
        content: Text(strings.localDeleteMessage(book.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(strings.importCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(strings.localDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
  }
  final removed = await controller.remove(book.key);
  if (removed && local && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.localCleanupPending
              ? strings.localCleanupPending
              : strings.localDeleted,
        ),
      ),
    );
  }
  return removed;
}
