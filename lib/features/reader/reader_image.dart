import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/source_image.dart';

const readerCaptionStyle = TextStyle(fontSize: 14, height: 1.4);

({double height, double caption}) readerImageExtent(
  ImageBlock block, {
  required double width,
  required double maxHeight,
  required TextScaler scaler,
  required TextDirection direction,
  Size? knownSize,
}) {
  var caption = 0.0;
  if (block.caption?.isNotEmpty ?? false) {
    final painter = TextPainter(
      text: TextSpan(text: block.caption, style: readerCaptionStyle),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: width);
    caption = math.min(painter.height + 16, maxHeight * .5);
    painter.dispose();
  }
  final size =
      knownSize ??
      (block.width != null && block.height != null
          ? Size(block.width!.toDouble(), block.height!.toDouble())
          : null);
  final desired = size == null ? 180.0 : width * size.height / size.width;
  final image = math.min(
    math.max(48.0, desired),
    math.max(0.0, maxHeight - caption),
  );
  return (height: image + caption, caption: caption);
}

class ReaderImage extends StatelessWidget {
  const ReaderImage({
    super.key,
    required this.block,
    required this.repository,
    required this.captionHeight,
    required this.onIntrinsicSize,
  });
  final ImageBlock block;
  final ImageRepository repository;
  final double captionHeight;
  final ValueChanged<Size> onIntrinsicSize;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: SizedBox(
          width: double.infinity,
          child: SourceImage(
            media: block.media,
            repository: repository,
            semanticLabel: block.alt,
            onIntrinsicSize: onIntrinsicSize,
          ),
        ),
      ),
      if (captionHeight > 0)
        SizedBox(
          height: captionHeight,
          width: double.infinity,
          child: Tooltip(
            message: block.caption!,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                block.caption!,
                style: readerCaptionStyle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
    ],
  );
}
