import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';

String? bookProgressLabel(
  AppLocalizations l,
  BookProgressSnapshot? progress, {
  bool descriptive = false,
}) {
  if (progress == null) return null;
  return switch (progress.terminal) {
    BookTerminalState.finished => l.bookFinished,
    BookTerminalState.caughtUp => l.bookCaughtUp,
    BookTerminalState.currentEnd => l.bookCurrentEnd,
    BookTerminalState.reading =>
      descriptive
          ? l.bookProgressPercent((progress.fraction * 100).round())
          : '${(progress.fraction * 100).round()}%',
  };
}
