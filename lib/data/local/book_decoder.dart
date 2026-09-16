import 'dart:typed_data';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/contracts/local_books.dart';
import '../../domain/contracts/cancellation.dart';
import '../../domain/models/models.dart';
import 'epub/epub_parser.dart';
import 'epub/epub_diagnostics.dart';
import 'local_guard.dart';
import 'parser_worker.dart';
import 'txt/txt_decoder.dart';
import 'txt/txt_parser.dart';

/// Stateless production decoder; sessions remain on the storage-owning isolate.
class BookDecoder implements LocalBookDecoder {
  const BookDecoder({this.epubDiagnostics});
  final EpubDiagnosticSlot? epubDiagnostics;
  static const parserVersion = 7;
  static const maxTxtBytes = 16 * 1024 * 1024;
  static const maxEpubBytes = 64 * 1024 * 1024;
  @override
  Future<LocalBookContent> decode(
    LocalImportSession session, {
    required LocalBookFormat format,
    required String filename,
    required CancellationToken cancellation,
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
  }) async {
    final builder = BytesBuilder(copy: false);
    final limit = format == LocalBookFormat.txt ? maxTxtBytes : maxEpubBytes;
    await for (final chunk in session.openOriginal()) {
      checkLocalCancellation(cancellation);
      if (builder.length + chunk.length > limit) {
        throw const LocalParseException(LocalParseProblem.tooLarge);
      }
      builder.add(chunk);
    }
    checkLocalCancellation(cancellation);
    final bytes = builder.takeBytes();
    final key = session.key;
    if (format == LocalBookFormat.txt) {
      final preview = await _inspect(bytes, encoding, cancellation);
      checkLocalCancellation(cancellation);
      TxtEncoding chosen;
      if (preview.detected case final detected?) {
        chosen = detected;
      } else {
        chosen = await Future.any([
          chooseEncoding(preview),
          cancellation.whenCancelled.then<TxtEncoding>(
            (_) => throw const LocalCancelled(),
          ),
        ]);
        if (!preview.samples.containsKey(chosen)) {
          throw const LocalParseException(LocalParseProblem.encoding);
        }
      }
      checkLocalCancellation(cancellation);
      return _txt(bytes, key, filename, chosen, cancellation);
    }
    final parsed = await _epub(bytes, key, filename, cancellation);
    for (final entry in parsed.media.entries) {
      checkLocalCancellation(cancellation);
      final ref = await session.writeMedia(Stream.value(entry.value));
      if (ref.mediaId != '${key.novelId}/${entry.key}') {
        throw const LocalParseException(LocalParseProblem.invalid);
      }
    }
    checkLocalCancellation(cancellation);
    epubDiagnostics?.record(parsed.diagnostics);
    return parsed.content;
  }
}

// Top-level wrappers ensure spawn closures cannot capture storage handles,
// controllers, pending UI completers or a LocalImportSession by accident.
Future<TxtEncodingPreview> _inspect(
  Uint8List b,
  TxtEncoding? e,
  CancellationToken t,
) => runParserWorker(() => inspectTxt(b, e), t);
Future<LocalBookContent> _txt(
  Uint8List b,
  NovelKey k,
  String f,
  TxtEncoding e,
  CancellationToken t,
) => runParserWorker(() => parseTxt(b, k, f, e), t);
Future<ParsedEpub> _epub(
  Uint8List b,
  NovelKey k,
  String f,
  CancellationToken t,
) => runParserWorker(() => EpubParser(b, k, f).parse(), t);
