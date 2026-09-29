import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'reader_tap_zones.dart';
import 'viewport/page_turn.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';

/// Reader chrome only: no synthetic chapter or content position.
class ReaderCompletionPage extends StatefulWidget {
  const ReaderCompletionPage({
    super.key,
    required this.state,
    required this.title,
    required this.onPrevious,
    required this.onExit,
    required this.onCatalog,
    required this.onRestart,
    required this.style,
    this.onToggleChrome,
    this.onDrag,
    this.chromeVisible = false,
    this.pageSize,
    this.contentOrigin = Offset.zero,
    this.padding = EdgeInsets.zero,
  });
  final BookTerminalState state;
  final String title;
  final VoidCallback onPrevious, onExit, onCatalog, onRestart;
  final TextStyle style;
  final VoidCallback? onToggleChrome;
  final BoundaryPageDrag? Function(double grip)? onDrag;
  final bool chromeVisible;
  final Size? pageSize;
  final Offset contentOrigin;
  final EdgeInsets padding;

  @override
  State<ReaderCompletionPage> createState() => _ReaderCompletionPageState();
}

class _ReaderCompletionPageState extends State<ReaderCompletionPage> {
  BoundaryPageDrag? _drag;
  double _distance = 0, _grip = pageTurnCentreGrip;
  int? _direction;
  bool _cancelled = false;
  double get _width =>
      widget.pageSize?.width ??
      (context.findRenderObject()! as RenderBox).size.width;
  double get _progress => (_distance / _width).clamp(0, 1);
  void _cancel() {
    _cancelled = true;
    _drag?.cancel();
    _drag = null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final heading = switch (widget.state) {
      BookTerminalState.finished => l.bookFinished,
      BookTerminalState.caughtUp => l.bookCaughtUp,
      _ => l.bookCurrentEnd,
    };
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = theme.colorScheme.primary;
    final cjk = Localizations.localeOf(context).languageCode == 'zh';
    // The page keeps the reading typeface; UI labels use fixed sizes so they
    // stay compact whatever body size the reader chose, while the title
    // follows the body size within bounds.
    final type = widget.style.copyWith(height: 1.5);
    final label = type.copyWith(fontSize: 14);
    final action = type.copyWith(fontSize: 15, fontWeight: FontWeight.w500);
    final titleSize = ((widget.style.fontSize ?? 20) * 1.25).clamp(24.0, 32.0);
    final secondary = TextButton.styleFrom(
      foregroundColor: muted,
      textStyle: label,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    );
    return Semantics(
      label: heading,
      onDecrease: widget.onPrevious,
      onIncrease: () {},
      child: Listener(
        onPointerCancel: (_) => _cancel(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            _cancelled = false;
            _distance = 0;
            _direction = null;
            _drag = null;
            final height =
                widget.pageSize?.height ??
                (context.findRenderObject()! as RenderBox).size.height;
            _grip = pageTurnGrip(
              details.localPosition.dy + widget.contentOrigin.dy,
              height,
            );
          },
          onHorizontalDragUpdate: (details) {
            if (_cancelled) return;
            _distance += details.delta.dx;
            _direction ??= _distance > 0 ? -1 : 1;
            if (_direction != -1) return;
            _drag ??= widget.onDrag?.call(_grip);
            _drag?.update(_progress);
          },
          onHorizontalDragEnd: (details) {
            if (_cancelled || _direction != -1) return;
            final commit = pageTurnCommits(
              _progress,
              details.primaryVelocity ?? 0,
            );
            final drag = _drag;
            _drag = null;
            if (drag != null) {
              drag.end(commit);
            } else if (commit) {
              widget.onPrevious();
            }
          },
          onHorizontalDragCancel: _cancel,
          onTapUp: (details) {
            switch (readerTapZone(
              details.localPosition.dx + widget.contentOrigin.dx,
              _width,
              chromeVisible: widget.chromeVisible,
            )) {
              case ReaderTap.previous:
                widget.onPrevious();
              case ReaderTap.center:
                widget.onToggleChrome?.call();
              case ReaderTap.next:
                break;
            }
          },
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(
              padding: widget.padding,
              child: LayoutBuilder(
                builder: (context, bounds) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: bounds.maxHeight),
                    // Slightly above centre, where a closing page reads balanced.
                    child: Align(
                      alignment: const Alignment(0, -.18),
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
                              CustomPaint(
                                size: const Size(18, 34),
                                painter: _RibbonPainter(accent),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                heading,
                                style: label.copyWith(
                                  color: accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  // CJK labels take airy tracking; Latin words
                                  // would fall apart at the same spacing.
                                  letterSpacing: cjk ? 3 : 1,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: ShioriSpace.medium),
                              Text(
                                widget.title,
                                style: type.copyWith(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: ShioriSpace.section),
                              _Ornament(color: ink.withValues(alpha: .22)),
                              const SizedBox(height: 56),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 220,
                                ),
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: ink.withValues(alpha: .08),
                                    foregroundColor: ink,
                                    // The fill is translucent: a hover shadow
                                    // would show through it and fade out on its
                                    // own, slower than the hover tint.
                                    elevation: 0,
                                    minimumSize: const Size(0, 50),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                      vertical: 14,
                                    ),
                                    shape: const StadiumBorder(),
                                    textStyle: action,
                                  ),
                                  onPressed: widget.onExit,
                                  child: Text(
                                    l.readerBackToShelf,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              const SizedBox(height: ShioriSpace.medium),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: ShioriSpace.small,
                                children: [
                                  TextButton.icon(
                                    style: secondary,
                                    onPressed: widget.onCatalog,
                                    icon: const Icon(Icons.list, size: 18),
                                    label: Text(l.readerViewCatalog),
                                  ),
                                  TextButton.icon(
                                    style: secondary,
                                    onPressed: widget.onRestart,
                                    icon: const Icon(
                                      Icons.replay_rounded,
                                      size: 18,
                                    ),
                                    label: Text(l.readerRestart),
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
        ),
      ),
    );
  }
}

/// The app's bookmark ribbon (栞): a flat strip with a swallowtail end.
class _RibbonPainter extends CustomPainter {
  const _RibbonPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final notch = size.width * .42;
    canvas.drawPath(
      Path()
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width / 2, size.height - notch)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.color != color;
}

/// A short rule broken by a small diamond, closing the title block.
class _Ornament extends StatelessWidget {
  const _Ornament({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final rule = SizedBox(width: 28, child: Divider(height: 1, color: color));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        rule,
        const SizedBox(width: 10),
        Transform.rotate(
          angle: math.pi / 4,
          child: SizedBox.square(dimension: 5, child: ColoredBox(color: color)),
        ),
        const SizedBox(width: 10),
        rule,
      ],
    );
  }
}
