import 'dart:typed_data';
import '../../../domain/models/models.dart';

/// Bounded signature screening; actual decoding remains the platform player's job.
AudioFormat? epubAudioFormat(Uint8List bytes) {
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WAVE') {
    return AudioFormat.wav;
  }
  if (bytes.length >= 10 && String.fromCharCodes(bytes.take(3)) == 'ID3') {
    return AudioFormat.mp3;
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0xff &&
      bytes[1] & 0xe0 == 0xe0 &&
      bytes[1] & 6 != 0 &&
      bytes[2] >> 4 != 0xf &&
      bytes[2] & 0xc != 0xc) {
    return AudioFormat.mp3;
  }
  return null;
}
