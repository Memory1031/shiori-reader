import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../app/theme/shiori_theme.dart';

/// Original vector artwork, authored for this offline lab. No external assets.
class LabCover extends StatelessWidget {
  const LabCover({
    super.key,
    required this.title,
    this.index = 0,
    this.missing = false,
  });
  final String title;
  final int index;
  final bool missing;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: ShioriShape.coverRatio,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(ShioriShape.cover),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: missing
            ? const Center(child: Icon(Icons.book_outlined, size: 36))
            : Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: CoverArtwork(index)),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final small = constraints.maxWidth < 110;
                      return Padding(
                        padding: EdgeInsets.all(small ? 8 : 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!small)
                              const Text(
                                'SHIORI  /  FICTION',
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontSize: 8,
                                  letterSpacing: 1.4,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            const Spacer(),
                            Text(
                              title,
                              maxLines: small ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: small ? 12 : 18,
                                height: 1.3,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const SizedBox(
                              width: 22,
                              child: Divider(color: Colors.white, thickness: 1),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
      ),
    ),
  );
}

class CoverArtwork extends CustomPainter {
  const CoverArtwork(this.index);
  final int index;
  @override
  void paint(Canvas canvas, Size size) {
    const colors = [
      Color(0xff566e7c),
      Color(0xff73566f),
      Color(0xff576b62),
      Color(0xffa06a50),
    ];
    final color = colors[index % colors.length];
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, const Color(0xff171f30), .68)!],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * .7, size.height * .23),
      size.width * .2,
      Paint()..color = const Color(0xfff7dfb6),
    );
    for (var i = 0; i < 3; i++) {
      final path = Path()..moveTo(0, size.height * (.48 + i * .1));
      for (var x = 0.0; x <= size.width + 4; x += 4) {
        path.lineTo(
          x,
          size.height * (.48 + i * .1) +
              math.sin(x / size.width * 4 + i + index) * size.height * .09,
        );
      }
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(color, const Color(0xff14202b), .35 + i * .2)!,
      );
    }
    final rail = Paint()
      ..color = const Color(0xffedc3a0)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width * .12, size.height * .46),
      Offset(size.width * .88, size.height * .38),
      rail,
    );
    for (var i = 0; i < 7; i++) {
      final x = size.width * (.12 + i * .12);
      canvas.drawLine(
        Offset(x, size.height * (.46 - i * .013)),
        Offset(x, size.height * .58),
        rail,
      );
    }
  }

  @override
  bool shouldRepaint(CoverArtwork oldDelegate) => oldDelegate.index != index;
}
