import 'package:flutter/material.dart';
import 'reader_tap_zones.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';

/// Reader chrome only: no synthetic chapter or content position.
class ReaderCompletionPage extends StatelessWidget {
  const ReaderCompletionPage({
    super.key,
    required this.state,
    required this.title,
    required this.onPrevious,
    required this.onExit,
    required this.onCatalog,
    required this.onRestart,
    required this.style,
  });
  final BookTerminalState state;
  final String title;
  final VoidCallback onPrevious, onExit, onCatalog, onRestart;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final heading = switch (state) {
      BookTerminalState.finished => l.bookFinished,
      BookTerminalState.caughtUp => l.bookCaughtUp,
      _ => l.bookCurrentEnd,
    };
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final type = style.copyWith(height: 1.5);
    final titleSize = ((style.fontSize ?? 20) * 1.25).clamp(24.0, 32.0);
    var drag = 0.0;
    return Semantics(
      label: heading,
      onDecrease: onPrevious,
      onIncrease: () {},
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => drag = 0,
        onHorizontalDragUpdate: (details) => drag += details.delta.dx,
        onHorizontalDragEnd: (details) {
          if (drag >= 48 || (details.primaryVelocity ?? 0) > 300) onPrevious();
        },
        onTapUp: (details) {
          final width = (context.findRenderObject()! as RenderBox).size.width;
          if (readerTapZone(details.localPosition.dx, width) ==
              ReaderTap.previous) {
            onPrevious();
          }
        },
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: LayoutBuilder(
            builder: (context, bounds) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: bounds.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 48,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            size: 28,
                            color: muted,
                          ),
                          const SizedBox(height: 28),
                          Text(
                            heading,
                            style: type.copyWith(
                              fontSize: 14,
                              color: muted,
                              letterSpacing: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            title,
                            style: type.copyWith(
                              fontSize: titleSize,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: 40,
                            child: Divider(
                              height: 1,
                              color: ink.withValues(alpha: .25),
                            ),
                          ),
                          const SizedBox(height: 56),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 208),
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: ink.withValues(alpha: .09),
                                foregroundColor: ink,
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    ShioriShape.cover,
                                  ),
                                ),
                                textStyle: type.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              onPressed: onExit,
                              child: Text(
                                l.readerBackToShelf,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: muted,
                                  textStyle: type.copyWith(fontSize: 14),
                                ),
                                onPressed: onCatalog,
                                child: Text(l.readerViewCatalog),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: muted,
                                  textStyle: type.copyWith(fontSize: 14),
                                ),
                                onPressed: onRestart,
                                child: Text(l.readerRestart),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
