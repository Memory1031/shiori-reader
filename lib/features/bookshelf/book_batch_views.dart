import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/shiori_sheet.dart';
import '../../shared/widgets/state_views.dart';
import 'book_selection_controller.dart';

/// Intrinsic width of batch dialog content; dialogs size to their widest
/// child and stretch these views to match.
const _contentWidth = 420.0;

/// The route a [BookBatchPanel] opens in: a dialog on pointer-first
/// platforms, a bottom sheet on touch ones. A route that is not
/// [dismissible] closes only through its own actions.
ModalRoute<T> bookBatchRoute<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = true,
}) => ShioriCapabilities.of(context).pointerFirst
    ? DialogRoute<T>(
        context: context,
        builder: builder,
        barrierDismissible: dismissible,
      )
    : shioriSheetRoute<T>(context, builder: builder, dismissible: dismissible);

class BookBatchAction {
  const BookBatchAction(
    this.label,
    this.onPressed, {
    this.primary = false,
    this.destructive = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary, destructive;
}

/// Batch confirmation, progress and result content laid out for the route
/// [bookBatchRoute] chose. Dialogs keep trailing text actions; sheets give
/// each action an equal share of a full-width row within thumb reach.
class BookBatchPanel extends StatelessWidget {
  const BookBatchPanel({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });
  final String title;
  final Widget content;
  final List<BookBatchAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destructive = FilledButton.styleFrom(
      foregroundColor: theme.colorScheme.onError,
      backgroundColor: theme.colorScheme.error,
    );
    if (ShioriCapabilities.of(context).pointerFirst) {
      return AlertDialog(
        constraints: const BoxConstraints(maxWidth: ShioriLayout.panel),
        title: Text(title),
        scrollable: true,
        content: content,
        actions: [
          for (final action in actions)
            action.primary
                ? FilledButton(
                    style: action.destructive ? destructive : null,
                    onPressed: action.onPressed,
                    child: Text(action.label),
                  )
                : TextButton(
                    onPressed: action.onPressed,
                    child: Text(action.label),
                  ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ShioriSpace.page,
        0,
        ShioriSpace.page,
        ShioriSpace.page,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: ShioriSpace.item),
          Flexible(child: SingleChildScrollView(child: content)),
          const SizedBox(height: ShioriSpace.page),
          Row(
            children: [
              for (final (i, action) in actions.indexed) ...[
                if (i > 0) const SizedBox(width: ShioriSpace.small),
                Expanded(
                  child: action.primary
                      ? FilledButton(
                          style: action.destructive ? destructive : null,
                          onPressed: action.onPressed,
                          child: Text(action.label),
                        )
                      : OutlinedButton(
                          onPressed: action.onPressed,
                          child: Text(action.label),
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class BookBatchProgressView extends StatelessWidget {
  const BookBatchProgressView({
    super.key,
    required this.title,
    required this.index,
    required this.total,
  });
  final String title;
  final int index, total;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _contentWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: ShioriSpace.medium),
              Text(
                '$index / $total',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: ShioriSpace.medium),
          ClipRRect(
            borderRadius: BorderRadius.circular(ShioriSpace.tight / 2),
            child: const LinearProgressIndicator(minHeight: ShioriSpace.tight),
          ),
        ],
      ),
    );
  }
}

class BookBatchRemovalNotice extends StatelessWidget {
  const BookBatchRemovalNotice({
    super.key,
    required this.local,
    required this.online,
  });
  final int local, online;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context),
        colors = Theme.of(context).colorScheme;
    Widget notice(IconData icon, String text, Color color) => Padding(
      padding: const EdgeInsets.only(top: ShioriSpace.medium),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: ShioriSpace.small),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (local > 0)
          notice(Icons.delete_outline, l.bookBatchLocal(local), colors.error),
        if (online > 0)
          notice(
            Icons.bookmark_remove_outlined,
            l.bookBatchOnline(online),
            colors.onSurfaceVariant,
          ),
      ],
    );
  }
}

/// A secondary line under batch dialog content, such as a cleanup notice.
class BookBatchNote extends StatelessWidget {
  const BookBatchNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ShioriSpace.small),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

/// Books listed in a rounded well so they read apart from the dialog copy.
/// Short lists size to their rows; longer ones scroll inside [height].
class _BookBatchList extends StatelessWidget {
  const _BookBatchList({
    required this.count,
    required this.builder,
    this.height = 180,
  });
  final int count;
  final IndexedWidgetBuilder builder;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(ShioriShape.control);
    Widget divider(BuildContext context, int _) => Divider(
      height: 1,
      thickness: 1,
      indent: _BookBatchRow.textIndent,
      endIndent: ShioriSpace.medium,
      color: colors.outlineVariant.withValues(alpha: .45),
    );
    return SizedBox(
      width: _contentWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: .6),
          borderRadius: radius,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: count <= 3
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.symmetric(
                      vertical: ShioriSpace.tight,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < count; i++) ...[
                          if (i > 0) divider(context, i),
                          builder(context, i),
                        ],
                      ],
                    ),
                  ),
                )
              : SizedBox(
                  height: height,
                  child: ListView.separated(
                    primary: false,
                    padding: const EdgeInsets.symmetric(
                      vertical: ShioriSpace.tight,
                    ),
                    itemCount: count,
                    itemBuilder: builder,
                    separatorBuilder: divider,
                  ),
                ),
        ),
      ),
    );
  }
}

class _BookBatchRow extends StatelessWidget {
  const _BookBatchRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    this.iconLabel,
  });
  final IconData icon;
  final String title;
  final String? subtitle, iconLabel;
  final Color? color;

  static const _iconSize = 18.0;
  static const textIndent = ShioriSpace.medium + _iconSize + ShioriSpace.medium;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ShioriSpace.medium,
        vertical: ShioriSpace.small,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: _iconSize,
              color: color ?? theme.colorScheme.onSurfaceVariant,
              semanticLabel: iconLabel,
            ),
          ),
          const SizedBox(width: ShioriSpace.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (subtitle case final subtitle?)
                  Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BookBatchPreview extends StatelessWidget {
  const BookBatchPreview({super.key, required this.books});
  final List<BookSelectionItem> books;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ShioriSpace.item),
    child: _BookBatchList(
      count: books.length,
      builder: (_, i) {
        final book = books[i];
        return _BookBatchRow(
          icon: !book.local
              ? Icons.bookmark_outline
              : book.format == LocalBookFormat.txt
              ? Icons.description_outlined
              : Icons.auto_stories_outlined,
          title: book.title,
        );
      },
    ),
  );
}

class BookBatchResultView extends StatelessWidget {
  const BookBatchResultView({
    super.key,
    required this.outcomes,
    this.excluded = 0,
  });
  final List<BookBatchOutcome> outcomes;
  final int excluded;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    int count(BookBatchStatus status) =>
        outcomes.where((r) => r.status == status).length;
    final attention = [
      ...outcomes.where(
        (r) =>
            r.status == BookBatchStatus.failed ||
            r.status == BookBatchStatus.unprocessed,
      ),
      ...outcomes.where(
        (r) =>
            r.status != BookBatchStatus.failed &&
            r.status != BookBatchStatus.unprocessed &&
            r.status != BookBatchStatus.succeeded,
      ),
    ];
    final completed = outcomes
        .where((r) => r.status == BookBatchStatus.succeeded)
        .toList();
    final failed = count(BookBatchStatus.failed);
    final unprocessed = count(BookBatchStatus.unprocessed);
    Widget row(BookBatchOutcome item) => _BookBatchRow(
      key: ValueKey(('batch-result', item.key)),
      icon: switch (item.status) {
        BookBatchStatus.succeeded => Icons.check_circle_outline,
        BookBatchStatus.failed => Icons.error_outline,
        BookBatchStatus.unprocessed => Icons.pause_circle_outline,
        BookBatchStatus.missing ||
        BookBatchStatus.inapplicable => Icons.remove_circle_outline,
      },
      color: switch (item.status) {
        BookBatchStatus.succeeded => colors.primary,
        BookBatchStatus.failed => colors.error,
        _ => null,
      },
      title: item.title,
      // The completed list's header already names the status; the icon
      // still announces it.
      iconLabel: item.status == BookBatchStatus.succeeded
          ? l.bookBatchSucceeded
          : null,
      subtitle: switch (item.status) {
        BookBatchStatus.succeeded => null,
        BookBatchStatus.failed => failureMessage(l, item.failure!),
        BookBatchStatus.unprocessed => l.bookBatchUnprocessed,
        BookBatchStatus.missing => l.bookBatchMissing,
        BookBatchStatus.inapplicable => l.bookBatchInapplicable,
      },
    );

    Widget items(List<BookBatchOutcome> rows) => _BookBatchList(
      count: rows.length,
      height: 240,
      builder: (_, i) => row(rows[i]),
    );
    return SizedBox(
      width: _contentWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  failed > 0
                      ? Icons.error_outline
                      : unprocessed > 0
                      ? Icons.pause_circle_outline
                      : Icons.check_circle_outline,
                  size: 20,
                  color: failed > 0
                      ? colors.error
                      : unprocessed > 0
                      ? colors.onSurfaceVariant
                      : colors.primary,
                ),
              ),
              const SizedBox(width: ShioriSpace.small),
              Expanded(
                child: Text(
                  l.bookBatchSummary(
                    count(BookBatchStatus.succeeded),
                    failed,
                    unprocessed,
                    count(BookBatchStatus.missing),
                    excluded + count(BookBatchStatus.inapplicable),
                  ),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (attention.isNotEmpty) ...[
            const SizedBox(height: ShioriSpace.medium),
            items(attention),
          ],
          if (completed.isNotEmpty)
            ListTileTheme.merge(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ShioriShape.control),
              ),
              child: ExpansionTile(
                // The header's hover wash spans the list's width, so its text
                // shares the rows' inset and a gap keeps the two surfaces apart.
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: ShioriSpace.medium,
                ),
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.only(top: ShioriSpace.small),
                expansionAnimationStyle: AnimationStyle(
                  duration: ShioriMotion.of(context, ShioriMotion.feedback),
                ),
                title: Text(
                  l.bookBatchSuccessDetails(completed.length),
                  style: theme.textTheme.bodyMedium,
                ),
                children: [items(completed)],
              ),
            )
          else if (attention.isNotEmpty)
            const SizedBox(height: ShioriSpace.small),
          if (excluded > 0 ||
              outcomes.any(
                (r) =>
                    r.status == BookBatchStatus.failed ||
                    r.status == BookBatchStatus.unprocessed ||
                    r.status == BookBatchStatus.inapplicable,
              ))
            BookBatchNote(l.bookBatchRemaining),
        ],
      ),
    );
  }
}
