import 'package:flutter/material.dart';
import '../../../domain/models/models.dart';
import '../reader_authored_colors.dart';

double readerBoxOuterWidth(ContentBlock block, double available) {
  final box = block.box;
  if (box == null) return available;
  final inset = 2 * (box.padding + box.borderWidth);
  final contentWidth = box.widthFraction == null
      ? box.width
      : available * box.widthFraction!;
  final maxWidth = box.maxWidthFraction == null
      ? box.maxWidth
      : available * box.maxWidthFraction!;
  return (contentWidth == null ? available : contentWidth + inset).clamp(
    1,
    (maxWidth == null ? available : maxWidth + inset).clamp(1, available),
  );
}

double readerBoxInnerWidth(ContentBlock block, double available) =>
    (readerBoxOuterWidth(block, available) -
            2 * ((block.box?.padding ?? 0) + (block.box?.borderWidth ?? 0)))
        .clamp(1, available);

({double top, double bottom}) readerBoxEdges(
  ChapterContent content,
  int index,
) {
  final box = content.blocks[index].box;
  if (box == null) return (top: 0, bottom: 0);
  final inset = box.padding + box.borderWidth;
  return (
    top: index == 0 || content.blocks[index - 1].box?.group != box.group
        ? inset
        : 0,
    bottom:
        index + 1 == content.blocks.length ||
            content.blocks[index + 1].box?.group != box.group
        ? inset
        : 0,
  );
}

class ReaderBoxFrame extends StatelessWidget {
  const ReaderBoxFrame({
    super.key,
    required this.box,
    required this.width,
    required this.top,
    required this.bottom,
    required this.child,
  });
  final BlockBox? box;
  final double width, top, bottom;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final b = box;
    if (b == null) return child;
    final colors = ReaderAuthoredColors(Theme.of(context));
    final background = b.backgroundColor == null
        ? null
        : colors.resolve(Color(b.backgroundColor!), ReaderColorRole.background);
    final border = colors.resolve(
      Color(b.borderColor ?? 0xff808080),
      ReaderColorRole.border,
      background: background,
    );
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: CustomPaint(
          painter: _BoxPainter(b, top > 0, bottom > 0, background, border),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              b.padding + b.borderWidth,
              top,
              b.padding + b.borderWidth,
              bottom,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.box, this.top, this.bottom, this.background, this.border);
  final Color? background;
  final Color border;
  final BlockBox box;
  final bool top, bottom;
  @override
  void paint(Canvas canvas, Size size) {
    if (background case final color?) {
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
    }
    if (box.borderWidth <= 0) return;
    final paint = Paint()
      ..color = border
      ..strokeWidth = box.borderWidth;
    void edge(Offset a, Offset b) {
      if (!box.dashed) {
        canvas.drawLine(a, b, paint);
        return;
      }
      final distance = (b - a).distance;
      if (distance == 0) return;
      final step = box.borderWidth * 4;
      for (var d = 0.0; d < distance; d += step * 1.6) {
        canvas.drawLine(
          a + (b - a) * (d / distance),
          a + (b - a) * ((d + step).clamp(0, distance) / distance),
          paint,
        );
      }
    }

    final half = box.borderWidth / 2;
    edge(Offset(half, 0), Offset(half, size.height));
    edge(Offset(size.width - half, 0), Offset(size.width - half, size.height));
    if (top) edge(Offset(0, half), Offset(size.width, half));
    if (bottom) {
      edge(
        Offset(0, size.height - half),
        Offset(size.width, size.height - half),
      );
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.box != box ||
      old.top != top ||
      old.bottom != bottom ||
      old.background != background ||
      old.border != border;
}
