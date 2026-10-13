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

/// Optional data-layer handoff owned by this import, never retained by a decoder.
abstract interface class EpubPresentationSession {
  void acceptPresentations((LocalBookContent, Map<String, String>)? value);
}

/// Stateless production decoder; sessions remain on the storage-owning isolate.
class BookDecoder implements LocalBookDecoder {
  const BookDecoder({this.epubDiagnostics});
  final EpubDiagnosticSlot? epubDiagnostics;
  static const parserVersion = 29;
  static const maxTxtBytes = LocalBookInputLimits.maxTxtBytes;
  static const maxEpubBytes = LocalBookInputLimits.maxEpubBytes;
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
    final (parsed, parser) = await _epub(
      bytes,
      key,
      filename,
      cancellation,
      session is EpubPresentationSession,
    );
    for (final entry in parsed.media.entries) {
      checkLocalCancellation(cancellation);
      final ref = await session.writeMedia(Stream.value(entry.value));
      if (ref.mediaId != '${key.novelId}/${entry.key}') {
        throw const LocalParseException(LocalParseProblem.invalid);
      }
    }
    checkLocalCancellation(cancellation);
    if (session is EpubPresentationSession) {
      (LocalBookContent, Map<String, String>)? presentations = (
        parsed.content,
        {},
      );
      if (parser != null) {
        try {
          presentations = await _renderEpub(
            parser,
            parsed.content,
            cancellation,
          );
        } on LocalParseException {
          // Optional renditions cannot discard successfully parsed native content.
          presentations = null;
        }
      }
      checkLocalCancellation(cancellation);
      (session as EpubPresentationSession).acceptPresentations(presentations);
    }
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
Future<(ParsedEpub, EpubParser?)> _epub(
  Uint8List b,
  NovelKey k,
  String f,
  CancellationToken t,
  bool retainPresentations,
) => runParserWorker(() {
  final parser = EpubParser(b, k, f);
  final parsed = parser.parse(retainPresentationInputs: retainPresentations);
  return (
    parsed,
    retainPresentations && parser.hasPresentationInputs ? parser : null,
  );
}, t);

Future<(LocalBookContent, Map<String, String>)> _renderEpub(
  EpubParser parser,
  LocalBookContent native,
  CancellationToken token,
) => runParserWorker(() => parser.renderForImport(native), token);
