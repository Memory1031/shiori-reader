import '../../domain/contracts/image_export.dart';
import '../../shared/image_export_scope.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/window_caption.dart';
import '../../app/theme/shiori_theme.dart';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/source_image.dart';

Future<void> showReaderImagePreview(
  BuildContext context, {
  required ImageBlock block,
  required ImageRepository repository,
  ImageExporter? exporter,
}) {
  final operation = exporter ?? ImageExportScope.maybeOf(context);
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      barrierDismissible: true,
      settings: const RouteSettings(name: '/reader-image'),
      transitionDuration: ShioriMotion.of(context, ShioriMotion.feedback),
      reverseTransitionDuration: ShioriMotion.of(
        context,
        ShioriMotion.feedback,
      ),
      pageBuilder: (_, _, _) => ReaderImagePreview(
        block: block,
        repository: repository,
        exporter: operation,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class ReaderImagePreview extends StatefulWidget {
  const ReaderImagePreview({
    super.key,
    required this.block,
    required this.repository,
    this.exporter,
  });
  final ImageBlock block;
  final ImageRepository repository;
  final ImageExporter? exporter;
  @override
  State<ReaderImagePreview> createState() => _ReaderImagePreviewState();
}

class _ReaderImagePreviewState extends State<ReaderImagePreview> {
  final _transform = TransformationController();
  bool _closing = false;
  CancellationSource? _exportCancellation;
  bool _busy = false;
  bool _lastAsFile = false;
  ImageExportResult? _feedback;

  bool get _active {
    if (!mounted || _closing) return false;
    final route = ModalRoute.of(context);
    return route != null && route.isActive && route.isCurrent;
  }

  Future<void> _save({bool asFile = false}) async {
    if (_busy || !_active) return;
    final exporter = widget.exporter;
    if (exporter == null) {
      setState(() => _feedback = ImageExportResult.unavailable);
      return;
    }
    final cancellation = _exportCancellation = CancellationSource();
    setState(() {
      _busy = true;
      _feedback = null;
      _lastAsFile = asFile;
    });
    ImageExportResult result;
    try {
      result = await exporter.save(
        repository: widget.repository,
        media: widget.block.media,
        cancellation: cancellation.token,
        asFile: asFile,
      );
    } catch (_) {
      result = ImageExportResult.unavailable;
    } finally {
      if (identical(_exportCancellation, cancellation)) {
        _exportCancellation = null;
      }
    }
    if (!mounted || _closing) return;
    final showFeedback = _active;
    setState(() {
      _busy = false;
      _feedback = !showFeedback || result == ImageExportResult.cancelled
          ? null
          : result;
    });
  }

  Widget _status(AppLocalizations strings) {
    final feedback = _feedback;
    final message = switch (feedback) {
      ImageExportResult.savedPhotos => strings.imageExportSavedPhotos,
      ImageExportResult.savedFile => strings.imageExportSavedFile,
      ImageExportResult.permissionDenied => strings.imageExportPermissionDenied,
      ImageExportResult.unsupportedFormat => strings.imageExportUnsupported,
      ImageExportResult.invalidFormat => strings.imageExportInvalidFormat,
      ImageExportResult.storageFailure => strings.imageExportStorageFailure,
      ImageExportResult.sourceUnavailable =>
        strings.imageExportSourceUnavailable,
      ImageExportResult.destinationExists => strings.imageExportExists,
      _ => strings.imageExportUnavailable,
    };
    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Material(
          color: Colors.black87,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .3,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(message, textAlign: TextAlign.center),
                    ),
                    if (feedback == ImageExportResult.unsupportedFormat)
                      TextButton(
                        onPressed: _busy ? null : () => _save(asFile: true),
                        child: Text(strings.imageExportAsFile),
                      ),
                    if ({
                      ImageExportResult.storageFailure,
                      ImageExportResult.sourceUnavailable,
                      ImageExportResult.destinationExists,
                      ImageExportResult.unavailable,
                    }.contains(feedback))
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _save(asFile: _lastAsFile),
                        child: Text(strings.retryAction),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _close() {
    if (!_active) return;
    _closing = true;
    _exportCancellation?.cancel();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _exportCancellation?.cancel();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // App typography (including the Windows UI face) on a true-black stage.
    final strings = AppLocalizations.of(context);
    final dark = shioriTheme(Brightness.dark, accent: appAccentOf(context));
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _closing = true;
          _exportCancellation?.cancel();
        }
      },
      child: WindowCaptionScope(
        appearance: (color: Colors.black, brightness: Brightness.dark),
        child: Theme(
          data: dark.copyWith(
            scaffoldBackgroundColor: Colors.black,
            colorScheme: dark.colorScheme.copyWith(
              surfaceContainerHighest: Colors.black,
            ),
          ),
          // Esc closes the preview wherever focus is, e.g. on the close button
          // after Tab or an arrow key: the Scaffold's own dismiss action, for
          // drawers, would otherwise hide the route's from it.
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _close,
            },
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    tooltip: _busy
                        ? strings.imageExportSaving
                        : strings.imageExportSave,
                    onPressed: _busy ? null : () => _save(),
                    icon: _busy
                        ? SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: strings.imageExportSaving,
                            ),
                          )
                        : Icon(
                            Icons.save_alt,
                            semanticLabel: strings.imageExportSave,
                          ),
                  ),
                  CloseButton(onPressed: _close),
                ],
              ),
              body: SafeArea(
                minimum: const EdgeInsets.only(bottom: 24),
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _close,
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
                          if (_feedback != null) _status(strings),
                        ],
                      ),
                    ),
                    if (widget.block.caption?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.all(ShioriSpace.item),
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
          ),
        ),
      ),
    );
  }
}
