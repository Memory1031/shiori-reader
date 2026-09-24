import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../source_image.dart';

/// Stable book silhouette, including when a source has no cover.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.images});
  final NovelSummary book;
  final ImageRepository? images;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(ShioriShape.cover),
    child: AspectRatio(
      aspectRatio: 2 / 3,
      child: book.cover != null && images != null
          ? SourceImage(
              media: book.cover!,
              repository: images!,
              semanticLabel: AppLocalizations.of(context).detailCover,
            )
          : ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border(
                    left: BorderSide(
                      width: 5,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .25),
                    ),
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.bookmark_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                ),
              ),
            ),
    ),
  );
}
