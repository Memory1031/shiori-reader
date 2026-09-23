import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Makes the white parts of a neutral SVG backdrop transparent at render time.
/// The EPUB bytes and positioned SVG text/hotspots remain unchanged.
Future<String> themedSvgPaperArtwork(String html, ui.Color ink) async {
  if (!html.contains('class="shiori-svg-page"')) return html;
  const prefixes = ['data:image/jpeg;base64,', 'data:image/png;base64,'];
  String? prefix;
  var start = -1;
  for (final candidate in prefixes) {
    start = html.indexOf(candidate);
    if (start >= 0) {
      prefix = candidate;
      break;
    }
  }
  if (prefix == null) return html;
  final end = html.indexOf('"', start);
  if (end < 0 || end - start > 11 * 1024 * 1024) return html;

  ui.ImmutableBuffer? sourceBuffer;
  ui.ImageDescriptor? sourceDescriptor;
  ui.Codec? sampleCodec;
  ui.Image? sample;
  ui.Codec? fullCodec;
  ui.Image? full;
  ui.ImmutableBuffer? outputBuffer;
  ui.ImageDescriptor? outputDescriptor;
  ui.Codec? outputCodec;
  ui.Image? output;
  try {
    final bytes = Uint8List.fromList(
      base64Decode(html.substring(start + prefix.length, end)),
    );
    sourceBuffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    sourceDescriptor = await ui.ImageDescriptor.encoded(sourceBuffer);
    final width = sourceDescriptor.width;
    final height = sourceDescriptor.height;
    if (width * height > 4000000) return html;
    final scale = 64 / (width > height ? width : height);
    sampleCodec = await sourceDescriptor.instantiateCodec(
      targetWidth: (width * scale).round().clamp(1, 64),
      targetHeight: (height * scale).round().clamp(1, 64),
    );
    sample = (await sampleCodec.getNextFrame()).image;
    final sampled = await sample.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (sampled == null ||
        !_isPaperArtwork(sampled, sample.width * sample.height)) {
      return html;
    }

    fullCodec = await sourceDescriptor.instantiateCodec();
    full = (await fullCodec.getNextFrame()).image;
    final pixels = await full.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) return html;
    final rgba = pixels.buffer.asUint8List(
      pixels.offsetInBytes,
      pixels.lengthInBytes,
    );
    final color = ink.toARGB32();
    final red = (color >> 16) & 0xff;
    final green = (color >> 8) & 0xff;
    final blue = color & 0xff;
    for (var at = 0; at < rgba.length; at += 4) {
      final luminance =
          (rgba[at] * 54 + rgba[at + 1] * 183 + rgba[at + 2] * 19) >> 8;
      final alpha = 255 - luminance;
      // PixelFormat.rgba8888 expects premultiplied channels.
      rgba[at] = (red * alpha + 127) ~/ 255;
      rgba[at + 1] = (green * alpha + 127) ~/ 255;
      rgba[at + 2] = (blue * alpha + 127) ~/ 255;
      rgba[at + 3] = alpha;
    }
    outputBuffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    outputDescriptor = ui.ImageDescriptor.raw(
      outputBuffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    outputCodec = await outputDescriptor.instantiateCodec();
    output = (await outputCodec.getNextFrame()).image;
    final png = await output.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return html;
    return html.replaceRange(
      start,
      end,
      'data:image/png;base64,${base64Encode(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))}',
    );
  } catch (_) {
    // Unsupported optional artwork keeps the EPUB's original appearance.
    return html;
  } finally {
    output?.dispose();
    outputCodec?.dispose();
    outputDescriptor?.dispose();
    outputBuffer?.dispose();
    full?.dispose();
    fullCodec?.dispose();
    sample?.dispose();
    sampleCodec?.dispose();
    sourceDescriptor?.dispose();
    sourceBuffer?.dispose();
  }
}

bool _isPaperArtwork(ByteData pixels, int count) {
  var white = 0;
  var colored = 0;
  for (var at = 0; at < pixels.lengthInBytes; at += 4) {
    if (pixels.getUint8(at + 3) < 250) return false;
    final red = pixels.getUint8(at);
    final green = pixels.getUint8(at + 1);
    final blue = pixels.getUint8(at + 2);
    final lowest = [red, green, blue].reduce((a, b) => a < b ? a : b);
    final highest = [red, green, blue].reduce((a, b) => a > b ? a : b);
    final chroma = highest - lowest;
    if (lowest >= 242 && chroma <= 12) white++;
    if (chroma > 24) colored++;
  }
  return white >= count * .85 && colored <= count * .005;
}
