import '../models/models.dart';
import 'cancellation.dart';
import 'result.dart';

abstract interface class UserBookmarkRepository {
  Stream<Result<BookmarkSnapshot>> watchBookmarks(NovelKey book);
  Future<Result<BookmarkSnapshot>> readBookmarks(
    NovelKey book, {
    required CancellationToken cancellation,
  });

  /// False means the user's snapshot was superseded; callers must refresh.
  Future<Result<bool>> saveBookmark(
    UserBookmark bookmark, {
    required int revision,
    required CancellationToken cancellation,
  });
  Future<Result<bool>> deleteBookmark(
    UserBookmark bookmark, {
    required CancellationToken cancellation,
  });
}
