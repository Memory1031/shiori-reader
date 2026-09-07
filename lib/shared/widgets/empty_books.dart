import 'package:flutter/material.dart';

/// Small code-native illustration; no remote asset or loading animation.
class EmptyBooks extends StatelessWidget {
  const EmptyBooks({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 120,
      height: 88,
      child: CustomPaint(painter: _BooksPainter(Theme.of(context).colorScheme)),
    ),
  );
}

class _BooksPainter extends CustomPainter {
  _BooksPainter(this.colors);
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = colors.primary;
    canvas.drawOval(
      Rect.fromLTWH(4, 72, 112, 12),
      Paint()..color = colors.primary.withValues(alpha: .08),
    );
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(19 + i * 28.0, 72);
      canvas.rotate((i - 1) * .13);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, -62 - i * 4, 25, 62 + i * 4),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = Color.lerp(
            colors.surfaceContainerHighest,
            colors.primary,
            .12 + i * .19,
          )!,
      );
      canvas.drawLine(
        const Offset(5, -50),
        const Offset(5, -6),
        Paint()
          ..color = colors.surface.withValues(alpha: .7)
          ..strokeWidth = 1,
      );
      canvas.drawLine(
        const Offset(10, -14),
        const Offset(19, -14),
        Paint()
          ..color = colors.surface
          ..strokeWidth = 2,
      );
      canvas.restore();
    }
    canvas.drawCircle(const Offset(105, 12), 3, ink);
  }

  @override
  bool shouldRepaint(_BooksPainter oldDelegate) => oldDelegate.colors != colors;
}
