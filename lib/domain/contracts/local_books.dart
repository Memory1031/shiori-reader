import 'dart:typed_data';
import '../content_identity.dart';
import '../models/models.dart';
import 'cancellation.dart';
import 'result.dart';
import 'local_book_decoder.dart';

enum LocalBookFormat { txt, epub }

/// Reserved namespace. IDs never contain an external path or a display title.
abstract final class LocalBookIdentity {
  static final sourceId = SourceId('local');
  static NovelKey book(String sha256) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw ArgumentError('Invalid file digest');
    }
    return NovelKey(sourceId: sourceId, novelId: sha256);
  }

  /// TXT: original section start code-point offset; EPUB: normalized spine href.
  /// Parser versions must preserve this policy, never use rendered pages.
  static ChapterKey epubOccurrence(NovelKey book, String path, int occurrence) {
    if (occurrence < 0) throw ArgumentError('Negative occurrence');
    return occurrence == 0
        ? chapter(book, 'epub:$path')
        : ChapterKey(
            novelKey: book,
            chapterId: ContentIdentity.digest('local-epub-occurrence', [
              path,
              occurrence,
            ]),
          );
  }

  static ChapterKey chapter(NovelKey book, String locator) => ChapterKey(
    novelKey: book,
    chapterId: ContentIdentity.digest('local-chapter', [locator]),
  );
}

final class LocalBookContent {
  LocalBookContent({
    required this.detail,
    required this.catalog,
    required Iterable<ChapterContent> chapters,
    Iterable<LocalNavigationEntry> navigation = const [],
    this.txtEncoding,
  }) : chapters = List.unmodifiable(chapters),
       navigation = List.unmodifiable(navigation);
  final TxtEncoding? txtEncoding;
  final NovelDetail detail;
  final Catalog catalog;
  final List<ChapterContent> chapters;
  final List<LocalNavigationEntry> navigation;
}

final class LocalBookRecord {
  const LocalBookRecord({
    required this.content,
    required this.format,
    required this.importedAt,
  });
  final LocalBookContent content;
  final LocalBookFormat format;
  final DateTime importedAt;
}

/// Valid only during the awaited parser callback. No paths or platform handles.
abstract interface class LocalImportSession {
  NovelKey get key;
  Stream<List<int>> openOriginal();
  Future<MediaRef> writeMedia(Stream<List<int>> bytes);
}

typedef LocalBookParser =
    Future<LocalBookContent> Function(LocalImportSession session);

/// Own one store per app lifetime; close before closing the user database.
/// Import publishes atomically after parsing. Existing files win on duplicates.
/// A committed success remains authoritative after cancellation.
abstract interface class LocalBookStore {
  Future<Result<LocalBookRecord>> importBook({
    required Stream<List<int>> bytes,
    required LocalBookFormat format,
    required LocalBookParser parse,
    bool addToShelf = false,
    required CancellationToken cancellation,
  });
  Future<Result<LocalBookRecord?>> read(
    NovelKey key, {
    required CancellationToken cancellation,
  });
  Future<Result<Uint8List>> readMedia(
    MediaRef ref, {
    required CancellationToken cancellation,
  });
  Future<void> close();
}

final class LocalBookInfo {
  const LocalBookInfo({
    required this.key,
    required this.title,
    required this.format,
    required this.importedAt,
  });
  final NovelKey key;
  final String title;
  final LocalBookFormat format;
  final DateTime importedAt;
}

final class LocalBookDeletion {
  const LocalBookDeletion({this.cleanupPending = false});
  final bool cleanupPending;
}

/// Separate from removing a shelf entry: deleting also removes owned files and
/// progress, and invalidates outstanding progress sessions atomically.
abstract interface class LocalBookManagement {
  Stream<Result<List<LocalBookInfo>>> watchBooks();
  Future<Result<LocalBookDeletion>> deleteBook(
    NovelKey key, {
    required CancellationToken cancellation,
  });
}

abstract interface class LocalNavigationRepository {
  Future<Result<List<LocalNavigationEntry>>> loadNavigation(
    NovelKey key, {
    required CancellationToken cancellation,
  });
}

/// Optional offline rendition alongside immutable semantic chapter content.
/// HTML is inert, self-contained and bounded by the data layer; never a URL.
abstract interface class LocalPagePresentationRepository {
  Future<Result<String?>> loadPagePresentation(
    ChapterKey chapter, {
    required CancellationToken cancellation,
  });
}

/// Emitted before maintenance; consumers must retire old reading controllers.
abstract interface class LocalBookInvalidation {
  Stream<NovelKey> get invalidations;
  Stream<NovelKey> get changes;
}

final class LocalReparseResult {
  const LocalReparseResult({
    required this.approximate,
    this.cleanupPending = false,
  });
  final bool approximate;
  final bool cleanupPending;
}

abstract interface class LocalBookReparse implements LocalBookInvalidation {
  Future<Result<LocalReparseResult>> reparseBook(
    NovelKey key, {
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
    required CancellationToken cancellation,
  });
}
