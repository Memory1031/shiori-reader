import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import 'reading_progress_format.dart';

/// Chapter scrubber with book progress and chapter stepping. Placement
/// agnostic: [onDone] closes whichever host shows it (sheet or side panel).
class ReaderProgressPanel extends StatefulWidget {
  const ReaderProgressPanel({
    super.key,
    required this.chapterTitle,
    required this.chapterFraction,
    required this.anchorFraction,
    required this.onSeek,
    required this.onDone,
    this.bookFractionAt,
    this.onPreviousChapter,
    this.onNextChapter,
    this.showChapterStepper = true,
  });
  final String chapterTitle;

  /// Visible extent of the page shown on the scrubber.
  final double chapterFraction;

  /// Resume anchor (page start) used for the book figure until scrubbing.
  final double anchorFraction;

  /// Book fraction for a chapter fraction; null when unknown.
  final double? Function(double chapterFraction)? bookFractionAt;
  final ValueChanged<double> onSeek;
  final VoidCallback onDone;
  final VoidCallback? onPreviousChapter, onNextChapter;
  final bool showChapterStepper;

  @override
  State<ReaderProgressPanel> createState() => _ReaderProgressPanelState();
}

class _ReaderProgressPanelState extends State<ReaderProgressPanel> {
  late double _fraction = widget.chapterFraction.clamp(0.0, 1.0);
  late double _bookBasis = widget.anchorFraction.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = widget.bookFractionAt?.call(_bookBasis);
    void step(VoidCallback? action) {
      if (action == null) return;
      widget.onDone();
      action();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ShioriSpace.page,
        0,
        ShioriSpace.page,
        ShioriSpace.item,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.readerReadingProgress,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (book != null)
                Text(
                  '${formatReadingPercent(book)}%',
                  style: theme.textTheme.titleMedium,
                ),
            ],
          ),
          const SizedBox(height: ShioriSpace.page),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: widget.chapterTitle,
                  child: Text(
                    widget.chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: ShioriSpace.item),
              Text('${formatReadingPercent(_fraction)}%'),
            ],
          ),
          Slider(
            value: _fraction,
            onChanged: (v) => setState(() {
              _fraction = v;
              _bookBasis = v;
            }),
            onChangeEnd: widget.onSeek,
          ),
          if (widget.showChapterStepper)
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: widget.onPreviousChapter == null
                        ? null
                        : () => step(widget.onPreviousChapter),
                    child: Text(l.previousChapter),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: widget.onNextChapter == null
                        ? null
                        : () => step(widget.onNextChapter),
                    child: Text(l.nextChapter),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
