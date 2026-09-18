import 'package:flutter/material.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/source_image.dart';

Future<void> showReaderImagePreview(
  BuildContext context, {
  required ImageBlock block,
  required ImageRepository repository,
}) => Navigator.of(context).push<void>(
  PageRouteBuilder<void>(
    settings: const RouteSettings(name: '/reader-image'),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150),
    reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 150),
    pageBuilder: (_, _, _) =>
        ReaderImagePreview(block: block, repository: repository),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class ReaderImagePreview extends StatefulWidget {
  const ReaderImagePreview({
    super.key,
    required this.block,
    required this.repository,
  });
  final ImageBlock block;
  final ImageRepository repository;
  @override
  State<ReaderImagePreview> createState() => _ReaderImagePreviewState();
}

class _ReaderImagePreviewState extends State<ReaderImagePreview> {
  final _transform = TransformationController();
  Offset _doubleTap = Offset.zero;
  void _toggleZoom() {
    if (_transform.value.getMaxScaleOnAxis() > 1.01) {
      _transform.value = Matrix4.identity();
    } else {
      const scale = 2.5;
      _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
        ..setTranslationRaw(
          -_doubleTap.dx * (scale - 1),
          -_doubleTap.dy * (scale - 1),
          0,
        );
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData.dark();
    return Theme(
      data: dark.copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: dark.colorScheme.copyWith(
          surfaceContainerHighest: Colors.black,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          actions: [CloseButton(onPressed: () => Navigator.pop(context))],
        ),
        body: SafeArea(
          minimum: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onDoubleTapDown: (details) =>
                      _doubleTap = details.localPosition,
                  onDoubleTap: _toggleZoom,
                  child: InteractiveViewer(
                    transformationController: _transform,
                    minScale: 1,
                    maxScale: 4,
                    child: SizedBox.expand(
                      child: SourceImage(
                        media: widget.block.media,
                        repository: widget.repository,
                        semanticLabel: widget.block.alt,
                        decodeScale: 2,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.block.caption?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.block.caption!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
