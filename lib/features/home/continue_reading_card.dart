import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_cover.dart';
import '../reader/book_progress_label.dart';

class ContinueReadingCard extends StatelessWidget {
  const ContinueReadingCard({
    super.key,
    required this.progress,
    required this.onContinue,
    this.images,
  });

  final ReadingProgress progress;
  final VoidCallback onContinue;
  final ImageRepository? images;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strings = AppLocalizations.of(context);
    final bookProgress = progress.bookProgress;
    final radius = BorderRadius.circular(ShioriShape.card);

    final progressSummary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          bookProgressLabel(
                strings,
                bookProgress,
                descriptive: true,
                wholePercent: true,
              ) ??
              strings.readerReadingProgress,
          style: theme.textTheme.bodySmall,
        ),
        if (bookProgress != null) ...[
          const SizedBox(height: ShioriSpace.small),
          ExcludeSemantics(
            child: LinearProgressIndicator(
              value: bookProgress.fraction,
              minHeight: 3,
              borderRadius: BorderRadius.circular(ShioriShape.indicator),
              color: colors.primary.withValues(alpha: .75),
              backgroundColor: colors.primary.withValues(alpha: .10),
              stopIndicatorRadius: 0,
            ),
          ),
        ],
      ],
    );
    final continueButton = TextButton(
      onPressed: onContinue,
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: ShioriSpace.small,
        ),
        textStyle: theme.textTheme.labelMedium,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              strings.homeContinueAction,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 2),
          const SizedBox(width: 10, child: Icon(Icons.chevron_right, size: 14)),
        ],
      ),
    );

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.lerp(colors.surface, colors.primary, .06)!,
              colors.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: InkWell(
          onTap: onContinue,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(ShioriSpace.item),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  child: BookCover(book: progress.snapshot, images: images),
                ),
                const SizedBox(width: ShioriSpace.item),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        progress.snapshot.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: ShioriSpace.small),
                      LayoutBuilder(
                        builder: (context, bounds) {
                          if (bounds.maxWidth < 190 ||
                              MediaQuery.textScalerOf(context).scale(14) > 20) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                progressSummary,
                                const SizedBox(height: ShioriSpace.small),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: continueButton,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: progressSummary),
                              const SizedBox(width: ShioriSpace.medium),
                              continueButton,
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
