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
      aspectRatio: ShioriShape.coverRatio,
      child: book.cover != null && images != null
          ? SourceImage(
              media: book.cover!,
              repository: images!,
              semanticLabel: AppLocalizations.of(context).detailCover,
            )
          : const CoverPlaceholder(),
    ),
  );
}

/// Spine-marked stand-in for a missing cover. [tinted] lifts the fill toward
/// the accent, e.g. to tell EPUB from TXT at a glance.
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    this.icon = Icons.bookmark_outline,
    this.tinted = false,
  });
  final IconData icon;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tinted
              ? Color.alphaBlend(
                  colors.primary.withValues(alpha: .10),
                  colors.surface,
                )
              : colors.surfaceContainerHighest,
          border: Border(
            left: BorderSide(
              width: 5,
              color: colors.primary.withValues(alpha: .25),
            ),
          ),
        ),
        child: Center(child: Icon(icon, color: colors.primary, size: 28)),
      ),
    );
  }
}
