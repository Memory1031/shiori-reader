import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/source_image.dart';
import 'reader_authored_colors.dart';
import '../../l10n/generated/app_localizations.dart';
import 'viewport/reader_box.dart';

const readerCaptionStyle = TextStyle(fontSize: 14, height: 1.4);

/// Used image pixels and caption reservation, in logical layout units. The
/// raster's encoded dimensions never include devicePixelRatio.
final class ReaderImageGeometry {
  const ReaderImageGeometry(this.size, this.caption, this.alignment, this.fit);
  final Size size;
  final double caption;
  final AlignmentGeometry alignment;
  final BoxFit fit;
  double get height => size.height + caption;
}

ReaderImageGeometry readerImageExtent(
  ImageBlock block, {
  required double width,
  required double maxHeight,
  required TextScaler scaler,
  required TextDirection direction,
  Size? knownSize,
  TextStyle style = const TextStyle(fontSize: 20),
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
  final room = math.max(0.0, maxHeight - caption);
  final sizing = block.sizing;
  // Old stored books and online sources retain the previous policy until an
  // EPUB reparse supplies explicit document-level sizing evidence.
  if (sizing == null) {
    final desired = size == null ? 180.0 : width * size.height / size.width;
    final height = math.min(math.max(48.0, desired), room);
    return ReaderImageGeometry(
      Size(width, height),
      caption,
      Alignment.center,
      BoxFit.contain,
    );
  }
  final em = scaler.scale((style.fontSize ?? 20) * sizing.fontScale);
  final authoredWidth =
      block.layout?.widthLength != null ||
      block.layout?.width != null ||
      block.layout?.widthFraction != null;
  final authoredHeight = sizing.height?.resolve(maxHeight, em);
  final maxImageHeight = math.min(
    room,
    sizing.maxHeight?.resolve(maxHeight, em) ?? room,
  );
  final ratio = size == null ? 1.0 : size.width / size.height;
  double w, h;
  if (authoredWidth) {
    w = width;
    h = authoredHeight ?? w / ratio;
  } else if (authoredHeight != null) {
    h = authoredHeight;
    w = h * ratio;
  } else if (size != null) {
    w = size.width;
    h = size.height;
  } else {
    w = math.min(math.min(width, room), 180.0);
    h = w;
  }
  final scale = w <= 0 || h <= 0
      ? 0.0
      : math.min(
          !authoredWidth &&
                  authoredHeight == null &&
                  sizing.role == ImageRole.page
              ? double.infinity
              : 1.0,
          math.min(width / w, maxImageHeight / h),
        );
  final alignment = switch (sizing.alignment ??
      (sizing.role == ImageRole.page
          ? ParagraphAlignment.center
          : ParagraphAlignment.start)) {
    ParagraphAlignment.center => Alignment.center,
    ParagraphAlignment.end => AlignmentDirectional.centerEnd,
    ParagraphAlignment.start => AlignmentDirectional.centerStart,
  };
  return ReaderImageGeometry(
    Size(w * scale, h * scale),
    caption,
    alignment,
    authoredWidth && authoredHeight != null ? BoxFit.fill : BoxFit.contain,
  );
}

/// The same container, edge budget, and image geometry are used by the Reader,
/// the paginator, and its invalidation signature.
ReaderImageGeometry readerImageForColumn(
  ImageBlock block, {
  required double width,
  required double height,
  required TextStyle style,
  required TextScaler scaler,
  required TextDirection direction,
  required ChapterContent content,
  required int blockIndex,
  Size? knownSize,
}) {
  final boxes = readerBlockBoxes(
    block,
    width,
    style,
    scaler,
    pageHeight: height,
  );
  final edges = readerBoxEdges(
    content,
    blockIndex,
    width: width,
    style: style,
    scaler: scaler,
    pageHeight: height,
  );
  return readerImageExtent(
    block,
    width: boxes.innerWidth,
    maxHeight: (height - edges.top - edges.bottom).clamp(0, height),
    style: style,
    scaler: scaler,
    direction: direction,
    knownSize: knownSize,
  );
}

class ReaderImage extends StatelessWidget {
  const ReaderImage({
    super.key,
    required this.block,
    required this.repository,
    required this.captionHeight,
    required this.onIntrinsicSize,
    this.onTap,
    this.geometry,
  });
  final ImageBlock block;
  final ImageRepository repository;
  final double captionHeight;
  final ValueChanged<Size> onIntrinsicSize;
  final VoidCallback? onTap;
  final ReaderImageGeometry? geometry;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: Semantics(
          button: onTap != null,
          label: onTap == null
              ? null
              : AppLocalizations.of(context).readerImagePreview,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              child: Align(
                alignment: geometry?.alignment ?? Alignment.center,
                child: SizedBox(
                  width: geometry?.size.width,
                  height: geometry?.size.height,
                  child: SourceImage(
                    fit: geometry?.fit ?? BoxFit.contain,
                    media: block.media,
                    repository: repository,
                    paperInk: ReaderAuthoredColors(
                      Theme.of(context),
                    ).resolve(Colors.black, ReaderColorRole.foreground),
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    semanticLabel: block.alt,
                    onIntrinsicSize: (size) {
                      if (block.width == size.width &&
                          block.height == size.height) {
                        return;
                      }
                      onIntrinsicSize(size);
                    },
                  ),
                ),
              ),
            ),
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
              padding: const EdgeInsets.symmetric(vertical: ShioriSpace.small),
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
