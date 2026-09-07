import '../../../domain/models/models.dart';
import 'lightnovel_api.dart';

/// Validated remote numeric IDs become opaque domain strings at this boundary.
/// Never default missing IDs to zero or derive identity from titles/order.
String lightNovelRemoteId(Object? value) {
  final text = value is int ? value.toString() : value;
  if (text is! String || !RegExp(r'^[1-9][0-9]*$').hasMatch(text)) {
    throw const FormatException('Invalid source identity');
  }
  return text;
}

NovelKey lightNovelKey(Object? bookId) =>
    NovelKey(sourceId: lightNovelSourceId, novelId: lightNovelRemoteId(bookId));
ChapterKey lightNovelChapterKey(NovelKey novel, Object? chapterId) {
  if (novel.sourceId != lightNovelSourceId) {
    throw const FormatException('Mismatched source identity');
  }
  return ChapterKey(novelKey: novel, chapterId: lightNovelRemoteId(chapterId));
}
