import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/contracts/contracts.dart';
import '../domain/models/models.dart';
import '../l10n/generated/app_localizations.dart';
import 'widgets/state_views.dart';

class ImageDecodeLimit implements Exception {
  const ImageDecodeLimit();
}

/// Returns a thumbnail size without upscaling; unusually large originals fail
/// before pixel decoding. This is independent of encoded byte limits.
({int width, int height}) imageDecodeSize(
  int width,
  int height,
  int targetWidth, {
  int maxPixels = 4000000,
}) {
  if (width < 1 ||
      height < 1 ||
      width > 32768 ||
      height > 32768 ||
      width * height > 100000000 ||
      targetWidth < 1 ||
      maxPixels < 1 ||
      maxPixels > 4000000) {
    throw const ImageDecodeLimit();
  }
  final scale = math.min(
    1.0,
    math.min(targetWidth / width, math.sqrt(maxPixels / (width * height))),
  );
  final w = math.max(1, (width * scale).floor());
  final h = math.min(math.max(1, (height * scale).floor()), maxPixels ~/ w);
  if (h < 1) throw const ImageDecodeLimit();
  return (width: w, height: h);
}

class DecodedSourceImage {
  const DecodedSourceImage(this.image, this.intrinsicSize);
  final ui.Image image;
  final Size intrinsicSize;
}

typedef SourceImageDecoder =
    Future<DecodedSourceImage> Function(MediaData data, int targetWidth);

/// Reader-owned decoded LRU. Only already mounted/nearby pages populate it;
/// downloading a volume never allocates decoded images for the entire volume.
class SourceImageDecodeScope extends StatefulWidget {
  const SourceImageDecodeScope({super.key, required this.child});
  final Widget child;
  @override
  State<SourceImageDecodeScope> createState() => _SourceImageDecodeScopeState();
}

class _SourceImageDecodeScopeState extends State<SourceImageDecodeScope> {
  final cache = _DecodedCache();
  @override
  void dispose() {
    cache.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _DecodeOwner(cache: cache, child: widget.child);
}

class _DecodeOwner extends InheritedWidget {
  const _DecodeOwner({required this.cache, required super.child});
  final _DecodedCache cache;
  @override
  bool updateShouldNotify(_DecodeOwner oldWidget) => cache != oldWidget.cache;
}

class _DecodedCache {
  final _entries = <(String, int), DecodedSourceImage>{};
  int _bytes = 0;
  bool _closed = false;
  Future<void> _tail = Future.value();
  Future<DecodedSourceImage> decode(MediaData data, int width) {
    final result = _tail.then((_) => _decode(data, width));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<DecodedSourceImage> _decode(MediaData data, int width) async {
    if (_closed) throw StateError('Reader decode scope closed');
    // Content-addressed persisted paths distinguish refreshed image versions.
    if (data is! LocalMedia) return decodeSourceImage(data, width);
    final key = (data.path, width);
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return DecodedSourceImage(existing.image.clone(), existing.intrinsicSize);
    }
    final decoded = await decodeSourceImage(data, width);
    if (_closed) return decoded;
    final duplicate = _entries.remove(key);
    if (duplicate != null) {
      _bytes -= duplicate.image.width * duplicate.image.height * 4;
      duplicate.image.dispose();
    }
    final size = decoded.image.width * decoded.image.height * 4;
    while (_entries.isNotEmpty &&
        (_bytes + size > 24 * 1024 * 1024 || _entries.length >= 5)) {
      final old = _entries.remove(_entries.keys.first)!;
      _bytes -= old.image.width * old.image.height * 4;
      old.image.dispose();
    }
    _entries[key] = DecodedSourceImage(
      decoded.image.clone(),
      decoded.intrinsicSize,
    );
    _bytes += size;
    return decoded;
  }

  void close() {
    _closed = true;
    for (final value in _entries.values) {
      value.image.dispose();
    }
    _entries.clear();
    _bytes = 0;
  }
}

Future<DecodedSourceImage> decodeSourceImage(
  MediaData data,
  int targetWidth,
) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    buffer = switch (data) {
      MemoryMedia(:final bytes) => await ui.ImmutableBuffer.fromUint8List(
        bytes,
      ),
      // The repository owns validation and file pinning; never a URL here.
      LocalMedia(:final path) => await ui.ImmutableBuffer.fromFilePath(path),
    };
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final original = Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    final size = imageDecodeSize(
      descriptor.width,
      descriptor.height,
      targetWidth,
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: size.width,
      targetHeight: size.height,
    );
    // MVP deliberately renders only the first frame, with no animation timer.
    final frame = await codec.getNextFrame();
    if (frame.image.width * frame.image.height > 4000000) {
      frame.image.dispose();
      throw const ImageDecodeLimit();
    }
    return DecodedSourceImage(frame.image, original);
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Shared cover/illustration view. Caller supplies bounds and owns repository;
/// this mounted widget owns its requests, independent lease and decoded image.
class SourceImage extends StatefulWidget {
  const SourceImage({
    super.key,
    required this.media,
    required this.repository,
    this.semanticLabel,
    this.placeholder,
    this.backgroundColor,
    this.onIntrinsicSize,
    this.decoder = decodeSourceImage,
    this.decodeScale = 1,
  }) : assert(decodeScale > 0 && decodeScale <= 4);
  final MediaRef media;
  final ImageRepository repository;
  final String? semanticLabel;
  final Widget? placeholder;
  final Color? backgroundColor;
  final ValueChanged<Size>? onIntrinsicSize;
  final SourceImageDecoder decoder;
  final double decodeScale;
  @override
  State<SourceImage> createState() => _SourceImageState();
}

class _SourceImageState extends State<SourceImage> {
  CancellationSource? _request;
  MediaLease? _lease;
  ui.Image? _image;
  AppFailure? _failure;
  Timer? _cooldown;
  Timer? _loadingDelay;
  bool _showLoading = false;
  bool _loading = true;
  int _generation = 0;
  int? _width;

  @override
  void didUpdateWidget(SourceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media != widget.media ||
        oldWidget.repository != widget.repository ||
        oldWidget.decoder != widget.decoder) {
      _generation++;
      _request?.cancel();
      _release();
      _width = null;
      _failure = null;
      _loading = true;
    }
  }

  void _release() {
    _image?.dispose();
    _image = null;
    final lease = _lease;
    _lease = null;
    if (lease != null) unawaited(lease.close());
  }

  @override
  void dispose() {
    _generation++;
    _request?.cancel();
    _cooldown?.cancel();
    _loadingDelay?.cancel();
    _release();
    super.dispose();
  }

  bool _current(int generation) => mounted && generation == _generation;

  Future<void> _load(int width, {bool refresh = false}) async {
    final shared = context.getInheritedWidgetOfExactType<_DecodeOwner>()?.cache;
    _request?.cancel();
    final request = _request = CancellationSource();
    final generation = ++_generation;
    _loadingDelay?.cancel();
    _showLoading = false;
    _loadingDelay = Timer(const Duration(milliseconds: 180), () {
      if (_current(generation) && _loading) setState(() => _showLoading = true);
    });
    _cooldown?.cancel();
    setState(() {
      _loading = true;
      _failure = null;
    });
    MediaLease? pendingLease;
    ui.Image? pendingImage;
    try {
      final result = await widget.repository.load(
        widget.media,
        mode: refresh ? ReadMode.refresh : ReadMode.cacheFirst,
        cancellation: request.token,
      );
      if (result case Failure(:final failure)) {
        if (_current(generation) && !failure.isCancellation) _fail(failure);
        return;
      }
      final loaded = (result as Success<LoadResult<MediaLease>>).value;
      pendingLease = loaded.value;
      if (!_current(generation)) return;
      final decoded =
          await (widget.decoder == decodeSourceImage && shared != null
              ? shared.decode(pendingLease.data, width)
              : widget.decoder(pendingLease.data, width));
      pendingImage = decoded.image;
      if (!_current(generation)) return;
      _release();
      setState(() {
        _lease = pendingLease;
        pendingLease = null;
        _image = pendingImage;
        pendingImage = null;
        _loading = false;
        _failure = loaded.refreshFailure ?? _lease!.persistenceFailure;
      });
      _scheduleCooldown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current(generation)) {
          widget.onIntrinsicSize?.call(decoded.intrinsicSize);
        }
      });
    } catch (error) {
      if (_current(generation)) {
        _fail(
          AppFailure(
            kind: error is ImageDecodeLimit
                ? FailureKind.tooLarge
                : FailureKind.parse,
            operation: Operation.media,
            retryPolicy: error is ImageDecodeLimit
                ? RetryPolicy.never
                : RetryPolicy.manual,
          ),
        );
      }
    } finally {
      pendingImage?.dispose();
      if (pendingLease != null) await pendingLease!.close();
      if (_current(generation) && _loading) setState(() => _loading = false);
    }
  }

  void _fail(AppFailure failure) {
    setState(() {
      _failure = failure;
      _loading = false;
    });
    _scheduleCooldown();
  }

  void _scheduleCooldown() {
    final until = _failure?.retryNotBefore;
    if (until != null && until.isAfter(DateTime.now())) {
      _cooldown = Timer(until.difference(DateTime.now()), () {
        if (mounted) setState(() {});
      });
    }
  }

  bool get _mayRetry =>
      !_loading &&
      _failure != null &&
      _failure!.retryPolicy != RetryPolicy.never &&
      (_failure!.kind != FailureKind.rateLimited ||
          (_failure!.retryNotBefore != null &&
              !DateTime.now().isBefore(_failure!.retryNotBefore!)));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width =
          ((bounds.hasBoundedWidth
                      ? bounds.maxWidth
                      : MediaQuery.sizeOf(context).width) *
                  MediaQuery.devicePixelRatioOf(context) *
                  widget.decodeScale)
              .ceil()
              .clamp(1, 32768);
      if (width != _width) {
        _width = width;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _width == width) unawaited(_load(width));
        });
      }
      final strings = AppLocalizations.of(context);
      Widget retry() => IconButton(
        tooltip: strings.retryAction,
        icon: const Icon(Icons.refresh),
        onPressed: _mayRetry ? () => _load(width, refresh: true) : null,
      );
      Widget body;
      if (_image != null) {
        body = Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              image: true,
              label: widget.semanticLabel ?? strings.readerImagePlaceholder,
              child: RawImage(
                image: _image,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
            if (_failure != null)
              Align(
                alignment: Alignment.bottomRight,
                child: Tooltip(
                  message: failureMessage(strings, _failure!),
                  child: retry(),
                ),
              ),
          ],
        );
      } else if (widget.placeholder != null) {
        body = widget.placeholder!;
      } else if (_failure != null) {
        body = Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: failureMessage(strings, _failure!),
                    child: Icon(
                      Icons.broken_image_outlined,
                      semanticLabel: failureMessage(strings, _failure!),
                    ),
                  ),
                  if (_failure!.retryPolicy != RetryPolicy.never) retry(),
                ],
              ),
            ),
          ),
        );
      } else {
        body = Center(
          child: SizedBox.square(
            dimension: 24,
            child: _loading && _showLoading
                ? CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: strings.loading,
                  )
                : Icon(
                    Icons.image_outlined,
                    semanticLabel: strings.readerImagePlaceholder,
                  ),
          ),
        );
      }
      return SizedBox(
        height: bounds.hasBoundedHeight ? null : 180,
        child: ColoredBox(
          color:
              widget.backgroundColor ??
              Theme.of(context).colorScheme.surfaceContainerHighest,
          child: body,
        ),
      );
    },
  );
}
