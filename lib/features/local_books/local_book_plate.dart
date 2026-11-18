import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/models/models.dart';

/// One library plate. The artwork keeps its proportions; dates and repair
/// messages may grow independently at large text sizes.
class LocalBookPlate extends StatelessWidget {
  const LocalBookPlate({
    super.key,
    required this.cover,
    required this.title,
    required this.format,
    required this.caption,
    required this.action,
    this.progress,
    this.issue,
  });
  final Widget cover, action;
  final String title, format, caption;
  final String? progress, issue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artwork = Stack(
      children: [
        AspectRatio(aspectRatio: ShioriShape.coverRatio, child: cover),
        PositionedDirectional(
          start: ShioriSpace.small,
          bottom: ShioriSpace.small,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .52),
              borderRadius: BorderRadius.circular(ShioriShape.tag),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                format,
                style: ShioriType.of(
                  context,
                ).badge.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          top: 0,
          end: 0,
          child: Stack(
            alignment: Alignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface.withValues(alpha: .94),
                ),
                child: const SizedBox.square(dimension: 28),
              ),
              SizedBox.square(
                dimension: kMinInteractiveDimension,
                child: action,
              ),
            ],
          ),
        ),
      ],
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: ShioriSpace.tight),
        Text(caption, style: theme.textTheme.bodySmall),
        if (progress != null) Text(progress!, style: theme.textTheme.bodySmall),
        if (issue != null)
          Text(
            issue!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth >= 240) {
          return Row(
            children: [
              SizedBox(width: 96, child: artwork),
              const SizedBox(width: ShioriSpace.item),
              Expanded(child: details),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            artwork,
            const SizedBox(height: ShioriSpace.medium),
            details,
          ],
        );
      },
    );
  }
}

/// A bookplate for files without cover art. Its initial and print stay
/// attached to the title, rather than changing when the library is filtered.
class FileBookplate extends StatelessWidget {
  const FileBookplate({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seed = title.runes.fold<int>(
      0,
      (sum, c) => (sum * 31 + c) & 0x7fffffff,
    );
    final accent = accentColor(
      AppAccent.values[seed % AppAccent.values.length],
      theme.brightness,
    );
    final solid = seed.isEven;
    final base = solid
        ? Color.lerp(accent, ShioriPalette.dark.paper, .2)!
        : Color.lerp(ShioriPalette.light.paper, accent, .24)!;
    final ink = solid
        ? ShioriPalette.light.paper
        : Color.lerp(accent, ShioriPalette.dark.paper, .55)!;
    final initial = title.trim().characters.firstOrNull;
    return ExcludeSemantics(
      child: ColoredBox(
        color: base,
        child: CustomPaint(
          painter: _Print(ink, seed % 3),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: FractionallySizedBox(
              widthFactor: .52,
              heightFactor: .38,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 14,
                  top: 10,
                  end: 8,
                  bottom: 8,
                ),
                child: initial == null
                    ? null
                    : FittedBox(
                        alignment: AlignmentDirectional.centerStart,
                        fit: BoxFit.contain,
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: ink,
                            height: 1,
                            fontWeight: FontWeight.w400,
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

class _Print extends CustomPainter {
  const _Print(this.ink, this.motif);
  final Color ink;
  final int motif;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = ink.withValues(alpha: .57)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    if (motif == 0) {
      // An engraved fan.
      final origin = Offset(w * .78, h * 1.07);
      for (var i = 0; i < 24; i++) {
        final a = math.pi * (1.03 + i / 28);
        canvas.drawLine(
          origin,
          origin + Offset(math.cos(a), math.sin(a)) * w * 1.01,
          paint,
        );
      }
      canvas.drawCircle(
        Offset(w * .74, h * .53),
        w * .11,
        Paint()..color = ink.withValues(alpha: .84),
      );
    } else if (motif == 1) {
      // Tidal contours.
      for (var i = 0; i < 11; i++) {
        final y = h * .54 + i * h * .049;
        canvas.drawPath(
          Path()
            ..moveTo(-w * .12, y)
            ..cubicTo(
              w * .28,
              y - h * .25,
              w * .52,
              y + h * .20,
              w * 1.12,
              y - h * .06,
            ),
          paint,
        );
      }
    } else {
      // An offset arch, like a window cut through the jacket.
      for (var i = 0; i < 10; i++) {
        final radius = w * (.18 + .064 * i);
        final rect = Rect.fromCircle(
          center: Offset(w * .72, h * .87),
          radius: radius,
        );
        canvas.drawPath(
          Path()
            ..moveTo(rect.left, h)
            ..lineTo(rect.left, rect.center.dy)
            ..arcTo(rect, math.pi, math.pi, false)
            ..lineTo(rect.right, h),
          paint,
        );
      }
    }
    canvas.drawLine(
      Offset(5, 0),
      Offset(5, h),
      Paint()..color = ink.withValues(alpha: .22),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Print old) => old.ink != ink || old.motif != motif;
}
