import '../models/models.dart';
import 'result.dart';
import 'prefetch.dart';

class CachedChapter {
  const CachedChapter({
    required this.key,
    required this.title,
    required this.imageCount,
    required this.savedImages,
  });
  final ChapterKey key;
  final String title;
  final int imageCount, savedImages;
}

class CacheOverview {
  CacheOverview({
    required this.textBytes,
    required this.imageBytes,
    required Iterable<CachedChapter> chapters,
    Map<NovelKey, String> books = const {},
  }) : chapters = List.unmodifiable(chapters),
       books = Map.unmodifiable(books);
  final Map<NovelKey, String> books;
  final int textBytes, imageBytes;
  final List<CachedChapter> chapters;
}

abstract interface class CacheManagement {
  ReadingPrefetch? get prefetch;
  Future<Result<CacheOverview>> inspect({NovelKey? novel});
  Future<Result<void>> clear({NovelKey? novel});
  void Function() pinChapter(ChapterKey chapter);
}
