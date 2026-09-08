import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared timing for chapter boundaries, page turns and drag settlement.
abstract final class PaperTurnMotion {
  static const duration = Duration(milliseconds: 280);
  static Future<void> settle(
    AnimationController controller, {
    double target = 1,
    bool reduced = false,
  }) {
    final distance = (target - controller.value).abs().clamp(0.0, 1.0);
    final milliseconds = reduced || distance == 0
        ? 0
        : (duration.inMilliseconds * distance).round().clamp(
            80,
            duration.inMilliseconds,
          );
    return controller
        .animateTo(
          target,
          duration: Duration(milliseconds: milliseconds),
          curve: Curves.easeOutCubic,
        )
        .orCancel;
  }
}

/// A bounded live-widget reveal. The folded back is blank paper, never a
/// screenshot or mirrored text. Platform-view clipping needs device validation.
class PaperTurnClipper extends CustomClipper<Path> {
  const PaperTurnClipper(
    this.progress,
    this.direction, {
    this.pageSize,
    this.contentOrigin = Offset.zero,
  });
  final double progress;
  final int direction;
  final Size? pageSize;
  final Offset contentOrigin;
  @override
  Path getClip(Size localSize) {
    final size = pageSize ?? localSize;
    final p = progress.clamp(0.0, 1.0);
    final bend = math.sin(p * math.pi) * size.width * .12;
    final x = size.width * (1 - p);
    final tilt = math.sin(p * math.pi) * size.width * .1;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(x - tilt, 0)
      ..quadraticBezierTo(x - bend, size.height * .5, x + tilt, size.height)
      ..lineTo(0, size.height)
      ..close();
    if (direction > 0) return path.shift(-contentOrigin);
    return path
        .transform(Matrix4.identity().scaledByDouble(-1, 1, 1, 1).storage)
        .shift(Offset(size.width, 0) - contentOrigin);
  }

  @override
  bool shouldReclip(PaperTurnClipper old) =>
      old.progress != progress ||
      old.direction != direction ||
      old.pageSize != pageSize ||
      old.contentOrigin != contentOrigin;
}

class PaperTurnFold extends StatelessWidget {
  const PaperTurnFold({
    super.key,
    required this.progress,
    required this.direction,
    required this.paper,
  });
  final double progress;
  final int direction;
  final Color paper;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _FoldPainter(progress, direction, paper),
      size: Size.infinite,
    ),
  );
}

class _FoldPainter extends CustomPainter {
  _FoldPainter(this.progress, this.direction, this.paper);
  final double progress;
  final int direction;
  final Color paper;
  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0 || p >= 1) return;
    if (direction < 0) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final wave = math.sin(p * math.pi);
    final x = size.width * (1 - p);
    final tilt = math.sin(p * math.pi) * size.width * .1;
    final bend = wave * size.width * .12;
    final foldWidth = wave * size.width * .19;
    final fold = Path()
      ..moveTo(x - tilt, 0)
      ..quadraticBezierTo(x - bend, size.height * .5, x + tilt, size.height)
      ..lineTo(x + foldWidth * .7 + tilt, size.height)
      ..quadraticBezierTo(
        x + foldWidth - bend * .25,
        size.height * .5,
        x + foldWidth * .7 - tilt,
        0,
      )
      ..close();
    canvas.drawShadow(
      fold,
      Colors.black.withValues(alpha: .32),
      12 * wave,
      true,
    );
    final dark = Color.lerp(paper, Colors.black, .16)!;
    final light = Color.lerp(paper, Colors.white, .12)!;
    canvas.drawPath(
      fold,
      Paint()
        ..shader = LinearGradient(
          colors: [dark, paper, light, paper],
          stops: const [0, .22, .65, 1],
        ).createShader(Rect.fromLTRB(x - bend, 0, x + foldWidth, size.height)),
    );
  }

  @override
  bool shouldRepaint(_FoldPainter old) =>
      old.progress != progress ||
      old.direction != direction ||
      old.paper != paper;
}
