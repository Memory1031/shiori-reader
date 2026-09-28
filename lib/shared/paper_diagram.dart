import 'dart:math' as math;
import 'dart:ui' as ui;

/// Optional, theme-independent ink mask, made only from the bounded thumbnail.
/// The caller owns the returned image. Null means preserve the original.
Future<ui.Image?> paperDiagramMask(ui.Image source) async {
  final count = source.width * source.height;
  if (count < 64 || count > 4000000) return null;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    final bytes = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return null;
    final rgba = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    var white = 0,
        dark = 0,
        middle = 0,
        colored = 0,
        broadTone = 0,
        colorArea = 0,
        broadInk = 0;
    for (var p = 0; p < count; p++) {
      final at = p * 4;
      // Transparency already works on paper; never reinterpret alpha as ink.
      if (rgba[at + 3] != 255) return null;
      final low = math.min(rgba[at], math.min(rgba[at + 1], rgba[at + 2]));
      final high = math.max(rgba[at], math.max(rgba[at + 1], rgba[at + 2]));
      if (high - low > 24) {
        colored++;
        var nearWhite = false, nearInk = false;
        final x = p % source.width, y = p ~/ source.width;
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            if (x + dx < 0 ||
                x + dx >= source.width ||
                y + dy < 0 ||
                y + dy >= source.height) {
              continue;
            }
            final q = ((y + dy) * source.width + x + dx) * 4;
            final min = math.min(rgba[q], math.min(rgba[q + 1], rgba[q + 2]));
            final max = math.max(rgba[q], math.max(rgba[q + 1], rgba[q + 2]));
            nearWhite |= min >= 242;
            nearInk |= max <= 80;
          }
        }
        if (!nearWhite || !nearInk) colorArea++;
      }
      final l = (rgba[at] * 54 + rgba[at + 1] * 183 + rgba[at + 2] * 19) >> 8;
      if (l >= 242) {
        white++;
      } else if (l <= 80) {
        dark++;
        final x = p % source.width, y = p ~/ source.width;
        if (x > 2 && x < source.width - 3 && y > 2 && y < source.height - 3) {
          bool ink(int q) {
            final r = q * 4;
            return math.max(rgba[r], math.max(rgba[r + 1], rgba[r + 2])) <= 80;
          }

          if (ink(p - 3) &&
              ink(p + 3) &&
              ink(p - 3 * source.width) &&
              ink(p + 3 * source.width)) {
            broadInk++;
          }
        }
      } else {
        middle++;
        // Gray antialias edges are narrow. Broad continuous gray areas are
        // photographic/shaded content, even when surrounded by white margins.
        final x = p % source.width, y = p ~/ source.width;
        if (x > 1 && x < source.width - 2 && y > 1 && y < source.height - 2) {
          bool tone(int q) {
            final r = q * 4;
            final v =
                (rgba[r] * 54 + rgba[r + 1] * 183 + rgba[r + 2] * 19) >> 8;
            return v > 80 && v < 242;
          }

          if (tone(p - 2) &&
              tone(p + 2) &&
              tone(p - 2 * source.width) &&
              tone(p + 2 * source.width)) {
            broadTone++;
          }
        }
      }
    }
    // Intentionally conservative: neutral paper, visible strokes, little
    // continuous tone. Slight palette quantization at edges remains acceptable.
    if (white < count * .72 ||
        dark < count * .0005 ||
        colored > count * .02 ||
        colorArea > count * .0012 ||
        colorArea > colored * .08 ||
        middle > count * .20 ||
        broadTone > count * .002 ||
        broadInk > count * .005) {
      return null;
    }
    for (var at = 0; at < rgba.length; at += 4) {
      final l = (rgba[at] * 54 + rgba[at + 1] * 183 + rgba[at + 2] * 19) >> 8;
      // White premultiplied mask; tint with srcIn at paint time. No theme
      // specific pixels/cache and no white fringes around antialiased strokes.
      final a = 255 - l;
      rgba[at] = rgba[at + 1] = rgba[at + 2] = rgba[at + 3] = a;
    }
    buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: source.width,
      height: source.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    codec = await descriptor.instantiateCodec();
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
