import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'reading_progress_format.dart';

String? bookProgressLabel(
  AppLocalizations l,
  BookProgressSnapshot? progress, {
  bool descriptive = false,
  bool wholePercent = false,
}) {
  if (progress == null) return null;
  final formatted = formatReadingPercent(progress.fraction);
  final percent = wholePercent ? formatted.split('.').first : formatted;
  return switch (progress.terminal) {
    BookTerminalState.finished => l.bookFinished,
    BookTerminalState.caughtUp => l.bookCaughtUp,
    BookTerminalState.currentEnd => l.bookCurrentEnd,
    BookTerminalState.reading =>
      descriptive ? l.bookProgressPercent(percent) : '$percent%',
  };
}
