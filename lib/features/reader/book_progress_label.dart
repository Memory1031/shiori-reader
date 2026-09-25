import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'reading_progress_format.dart';

String? bookProgressLabel(
  AppLocalizations l,
  BookProgressSnapshot? progress, {
  bool descriptive = false,
}) {
  if (progress == null) return null;
  final percent = formatReadingPercent(progress.fraction);
  return switch (progress.terminal) {
    BookTerminalState.finished => l.bookFinished,
    BookTerminalState.caughtUp => l.bookCaughtUp,
    BookTerminalState.currentEnd => l.bookCurrentEnd,
    BookTerminalState.reading =>
      descriptive ? l.bookProgressPercent(percent) : '$percent%',
  };
}
