import 'package:flutter/material.dart';
import '../../shared/capabilities.dart';
import '../../app/theme/shiori_theme.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_cover.dart';

/// Cover and metadata side by side, with tags across the full width below.
class DetailBookHeader extends StatelessWidget {
  const DetailBookHeader({super.key, required this.detail, this.images});
  final NovelDetail detail;
  final ImageRepository? images;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, bounds) {
          final stacked =
              bounds.maxWidth < 340 ||
              bounds.maxWidth < 560 &&
                  MediaQuery.textScalerOf(context).scale(20) > 28;
          final cover = SizedBox(
            width: WindowClass.forWidth(bounds.maxWidth) == WindowClass.compact
                ? 104
                : 120,
            child: DetailCover(book: detail.summary, images: images),
          );
          final metadata = DetailBookInfo(detail: detail);
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: cover),
                const SizedBox(height: 24),
                metadata,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              const SizedBox(width: 24),
              Expanded(child: metadata),
            ],
          );
        },
      ),
      if (detail.tags.isNotEmpty) ...[
        const SizedBox(height: ShioriSpace.page),
        DetailTags(tags: detail.tags),
      ],
    ],
  );
}

/// The book cover, raised off the page; its width comes from the parent.
class DetailCover extends StatelessWidget {
  const DetailCover({super.key, required this.book, this.images});
  final NovelSummary book;
  final ImageRepository? images;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(ShioriShape.cover),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).colorScheme.shadow.withValues(alpha: .12),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: BookCover(book: book, images: images),
  );
}

/// Title, authors and status. The title always wraps in full; authors are
/// cut to [authorLines] when given, with the full list on hover.
class DetailBookInfo extends StatelessWidget {
  const DetailBookInfo({super.key, required this.detail, this.authorLines});
  final NovelDetail detail;
  final int? authorLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = detail.summary;
    final strings = AppLocalizations.of(context);
    final authorStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final authors = book.authors.join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(book.title, style: ShioriType.of(context).displayTitle),
        ),
        if (book.authors.isNotEmpty) ...[
          const SizedBox(height: ShioriSpace.medium),
          if (authorLines case final lines?)
            LayoutBuilder(
              builder: (context, bounds) {
                final text = Text(
                  authors,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: authorStyle,
                );
                // The text keeps the full list for assistive technology.
                return _exceeds(context, authors, authorStyle, lines, bounds)
                    ? Tooltip(
                        message: authors,
                        excludeFromSemantics: true,
                        child: text,
                      )
                    : text;
              },
            )
          else
            Text(authors, style: authorStyle),
        ],
        if (detail.status != NovelStatus.unknown) ...[
          const SizedBox(height: ShioriSpace.medium),
          Text(switch (detail.status) {
            NovelStatus.ongoing => strings.detailStatusOngoing,
            NovelStatus.completed => strings.detailStatusCompleted,
            NovelStatus.hiatus => strings.detailStatusHiatus,
            NovelStatus.unknown => strings.detailStatusUnknown,
          }, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Tags on two lines, expandable.
class DetailTags extends StatelessWidget {
  const DetailTags({super.key, required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) => _ExpandableText(
    text: tags.join(' · '),
    lines: 2,
    style: Theme.of(context).textTheme.bodySmall!,
    toggleKey: const ValueKey('detail-tags-toggle'),
  );
}

class DetailSynopsis extends StatelessWidget {
  const DetailSynopsis({super.key, required this.text, this.lines = 5});
  final String text;

  /// Lines shown before the synopsis is expanded.
  final int lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (text.trim().isEmpty) {
      return Text(
        AppLocalizations.of(context).detailNoSynopsis,
        style: theme.textTheme.bodySmall,
      );
    }
    return _ExpandableText(
      text: text,
      lines: lines,
      style: theme.textTheme.bodyLarge!,
      toggleKey: const ValueKey('detail-synopsis-toggle'),
    );
  }
}

/// Whether [text] needs more than [lines] lines in [bounds].
bool _exceeds(
  BuildContext context,
  String text,
  TextStyle? style,
  int lines,
  BoxConstraints bounds,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: lines,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.localeOf(context),
  )..layout(maxWidth: bounds.maxWidth);
  final exceeds = painter.didExceedMaxLines;
  painter.dispose();
  return exceeds;
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({
    required this.text,
    required this.lines,
    required this.style,
    required this.toggleKey,
  });
  final String text;
  final int lines;
  final TextStyle style;
  final Key toggleKey;
  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;
  @override
  void didUpdateWidget(_ExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final overflows = _exceeds(
        context,
        widget.text,
        widget.style,
        widget.lines,
        bounds,
      );
      final strings = AppLocalizations.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.text,
            style: widget.style,
            maxLines: _expanded ? null : widget.lines,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (overflows)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: widget.toggleKey,
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? strings.detailShowLess : strings.detailShowMore,
                ),
              ),
            ),
        ],
      );
    },
  );
}
