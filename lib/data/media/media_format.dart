import '../../domain/contracts/media.dart';

// Encoded signatures, shared by repository validation and original export.
MediaFormat detectMediaFormat(List<int> bytes) {
  bool prefix(List<int> value) =>
      bytes.length >= value.length &&
      List.generate(value.length, (i) => bytes[i] == value[i]).every((v) => v);
  if (prefix([137, 80, 78, 71, 13, 10, 26, 10])) return MediaFormat.png;
  if (prefix([255, 216, 255])) return MediaFormat.jpeg;
  if (prefix([71, 73, 70, 56, 55, 97]) || prefix([71, 73, 70, 56, 57, 97])) {
    return MediaFormat.gif;
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return MediaFormat.webp;
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.skip(4).take(4)) == 'ftyp' &&
      {'avif', 'avis'}.contains(String.fromCharCodes(bytes.skip(8).take(4)))) {
    return MediaFormat.avif;
  }
  return MediaFormat.unknown;
}
