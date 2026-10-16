import 'identity.dart';
import '../content_identity.dart';
import 'reader.dart';

/// Only exact and migrated results are navigable; no guessed position is saved.
enum BookmarkLocation { exact, migrated, inexact, unavailable }

final class BookmarkAnchor {
  BookmarkAnchor({
    required this.position,
    required this.quote,
    required this.quoteOffset,
    required this.unique,
    required this.blockDigest,
  }) {
    ContentIdentity.validateUnicode(quote);
    if (quote.runes.length > 64 ||
        quoteOffset < 0 ||
        quoteOffset > quote.runes.length) {
      throw ArgumentError('Invalid bookmark context');
    }
  }
  final ReaderPosition position;
  final String quote, blockDigest;
  final int quoteOffset;
  final bool unique;
  Map<String, Object?> toJson() => {
    'version': 1,
    'revision': position.contentRevision,
    'block': position.blockKey,
    'index': position.blockIndex,
    'fraction': position.blockFraction,
    'chapterFraction': position.chapterFraction,
    'quote': quote,
    'offset': quoteOffset,
    'unique': unique,
    'digest': blockDigest,
  };
  factory BookmarkAnchor.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('Bookmark version');
    return BookmarkAnchor(
      position: ReaderPosition(
        contentRevision: json['revision'] as String,
        blockKey: json['block'] as String,
        blockIndex: json['index'] as int,
        blockFraction: (json['fraction'] as num).toDouble(),
        chapterFraction: (json['chapterFraction'] as num).toDouble(),
      ),
      quote: json['quote'] as String,
      quoteOffset: json['offset'] as int,
      unique: json['unique'] as bool,
      blockDigest: json['digest'] as String,
    );
  }
}

final class UserBookmark {
  const UserBookmark({
    required this.id,
    required this.chapter,
    required this.anchor,
    required this.chapterTitle,
    required this.createdAt,
    this.version = 1,
    this.location = BookmarkLocation.exact,
  });
  final String id, chapterTitle;
  final ChapterKey chapter;
  final BookmarkAnchor anchor;
  final DateTime createdAt;
  final int version;
  final BookmarkLocation location;
  bool get located =>
      location == BookmarkLocation.exact ||
      location == BookmarkLocation.migrated;
  UserBookmark resolved(
    ChapterKey target,
    BookmarkAnchor next,
    BookmarkLocation state,
  ) => UserBookmark(
    id: id,
    chapter: target,
    anchor: next,
    chapterTitle: chapterTitle,
    createdAt: createdAt,
    version: version + 1,
    location: state,
  );
}

final class BookmarkSnapshot {
  BookmarkSnapshot(this.revision, Iterable<UserBookmark> bookmarks)
    : bookmarks = List.unmodifiable(bookmarks);
  final int revision;
  final List<UserBookmark> bookmarks;
}
