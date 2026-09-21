import 'package:flutter/material.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_cover.dart';

class DetailBookHeader extends StatelessWidget {
  const DetailBookHeader({super.key, required this.detail, this.images});
  final NovelDetail detail;
  final ImageRepository? images;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = detail.summary;
    final strings = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, bounds) {
            final stacked =
                bounds.maxWidth < 340 ||
                bounds.maxWidth < 560 &&
                    MediaQuery.textScalerOf(context).scale(20) > 28;
            final cover = SizedBox(
              width: bounds.maxWidth >= 600 ? 120 : 104,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: .12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: BookCover(book: book, images: images),
              ),
            );
            final metadata = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    book.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      height: 1.35,
                    ),
                  ),
                ),
                if (book.authors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    book.authors.join(', '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (detail.status != NovelStatus.unknown) ...[
                  const SizedBox(height: 12),
                  Text(switch (detail.status) {
                    NovelStatus.ongoing => strings.detailStatusOngoing,
                    NovelStatus.completed => strings.detailStatusCompleted,
                    NovelStatus.hiatus => strings.detailStatusHiatus,
                    NovelStatus.unknown => strings.detailStatusUnknown,
                  }, style: theme.textTheme.bodySmall),
                ],
              ],
            );
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
          const SizedBox(height: 20),
          _ExpandableText(
            text: detail.tags.join(' · '),
            lines: 2,
            style: theme.textTheme.bodySmall!,
            toggleKey: const ValueKey('detail-tags-toggle'),
          ),
        ],
      ],
    );
  }
}

class DetailSynopsis extends StatelessWidget {
  const DetailSynopsis({super.key, required this.text});
  final String text;

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
      lines: 5,
      style: theme.textTheme.bodyLarge!,
      toggleKey: const ValueKey('detail-synopsis-toggle'),
    );
  }
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
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: widget.lines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.localeOf(context),
      )..layout(maxWidth: bounds.maxWidth);
      final overflows = painter.didExceedMaxLines;
      painter.dispose();
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
