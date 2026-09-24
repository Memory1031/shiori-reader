import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared timing for chapter boundaries, page turns and drag settlement.
abstract final class PaperTurnMotion {
  static const duration = Duration(milliseconds: 280);
  static Future<void> settle(
    AnimationController controller, {
    double target = 1,
    bool reduced = false,
    Curve curve = Curves.easeOutCubic,
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
          curve: curve,
        )
        .orCancel;
  }
}

/// Crease geometry shared by the clip and the fold painter so the folded
/// back always meets the cut edge exactly.
///
/// The crease is a quadratic curve from the top to the bottom of the page.
/// It leans towards [grip] — the fraction of the height where the page is
/// held — so the corner nearest the finger travels furthest, as with paper
/// lifted at that point. The lean and bow peak mid-turn and vanish at rest.
class _Crease {
  _Crease(double progress, Size size, double grip) {
    final p = progress.clamp(0.0, 1.0);
    wave = math.sin(p * math.pi);
    x = size.width * (1 - p);
    // The held corner travels furthest: a grip below centre pulls the
    // bottom of the crease left of the top, and one above does the reverse.
    // At the centre the crease keeps the classic top-first lean.
    final lean = (grip - .5).clamp(-.35, .35) * 2;
    tilt = wave * size.width * (.1 + .06 * lean.abs()) * (lean > 0 ? -1 : 1);
    bend = wave * size.width * .12;
    control = Offset(x - bend, size.height * grip.clamp(.15, .85));
    top = Offset(x - tilt, 0);
    bottom = Offset(x + tilt, size.height);
    foldWidth = wave * size.width * .19;
  }
  late final double wave, x, tilt, bend, foldWidth;
  late final Offset top, bottom, control;
}

/// A bounded live-widget reveal. The folded back is blank paper, never a
/// screenshot or mirrored text. Platform-view clipping needs device validation.
class PaperTurnClipper extends CustomClipper<Path> {
  const PaperTurnClipper(
    this.progress,
    this.direction, {
    this.pageSize,
    this.contentOrigin = Offset.zero,
    this.grip = .5,
  });
  final double progress;
  final int direction;
  final Size? pageSize;
  final Offset contentOrigin;
  final double grip;
  @override
  Path getClip(Size localSize) {
    final size = pageSize ?? localSize;
    final c = _Crease(progress, size, grip);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(c.top.dx, 0)
      ..quadraticBezierTo(c.control.dx, c.control.dy, c.bottom.dx, size.height)
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
      old.contentOrigin != contentOrigin ||
      old.grip != grip;
}

class PaperTurnFold extends StatelessWidget {
  const PaperTurnFold({
    super.key,
    required this.progress,
    required this.direction,
    required this.paper,
    this.grip = .5,
  });
  final double progress;
  final int direction;
  final Color paper;
  final double grip;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _FoldPainter(progress, direction, paper, grip),
      size: Size.infinite,
    ),
  );
}

class _FoldPainter extends CustomPainter {
  _FoldPainter(this.progress, this.direction, this.paper, this.grip);
  final double progress;
  final int direction;
  final Color paper;
  final double grip;
  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0 || p >= 1) return;
    if (direction < 0) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final c = _Crease(p, size, grip);
    final dark = paper.computeLuminance() < .2;

    // Lift shadow: the revealed page darkens just past the crease, where the
    // raised sheet still blocks light.
    final lift = Path()
      ..moveTo(c.top.dx, 0)
      ..quadraticBezierTo(c.control.dx, c.control.dy, c.bottom.dx, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(
      lift,
      Paint()
        ..shader =
            LinearGradient(
              colors: [
                Colors.black.withValues(alpha: (dark ? .30 : .16) * c.wave),
                Colors.black.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromLTRB(
                c.x - c.bend,
                0,
                c.x + c.foldWidth * 1.6,
                size.height,
              ),
            ),
    );

    // Folded back of the sheet, lying over the revealed page.
    final back = Offset(c.foldWidth * .7, 0);
    final fold = Path()
      ..moveTo(c.top.dx, 0)
      ..quadraticBezierTo(c.control.dx, c.control.dy, c.bottom.dx, size.height)
      ..lineTo(c.bottom.dx + back.dx, size.height)
      ..quadraticBezierTo(
        c.x + c.foldWidth - c.bend * .25,
        c.control.dy,
        c.top.dx + back.dx,
        0,
      )
      ..close();
    canvas.drawShadow(
      fold,
      Colors.black.withValues(alpha: dark ? .5 : .32),
      12 * c.wave,
      true,
    );
    final shade = Color.lerp(paper, Colors.black, dark ? .28 : .16)!;
    final sheen = Color.lerp(paper, Colors.white, dark ? .06 : .14)!;
    canvas.drawPath(
      fold,
      Paint()
        ..shader =
            LinearGradient(
              colors: [shade, paper, sheen, paper],
              stops: const [0, .22, .6, 1],
            ).createShader(
              Rect.fromLTRB(c.x - c.bend, 0, c.x + c.foldWidth, size.height),
            ),
    );

    // Crease highlight: a thin bright line where the paper bends.
    canvas.drawPath(
      Path()
        ..moveTo(c.top.dx, 0)
        ..quadraticBezierTo(
          c.control.dx,
          c.control.dy,
          c.bottom.dx,
          size.height,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: (dark ? .10 : .45) * c.wave),
    );
  }

  @override
  bool shouldRepaint(_FoldPainter old) =>
      old.progress != progress ||
      old.direction != direction ||
      old.paper != paper ||
      old.grip != grip;
}
