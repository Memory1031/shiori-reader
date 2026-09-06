import '../models/models.dart';
import '../models/value_model.dart';
import 'cancellation.dart';
import 'result.dart';

final class SourceDescriptor extends ValueModel {
  SourceDescriptor({
    required this.sourceId,
    required String displayName,
    required this.supportsDiscover,
    required this.supportsSearchPaging,
  }) : displayName = nonBlank(displayName, 'displayName');
  final SourceId sourceId;
  final String displayName;
  final bool supportsDiscover;
  final bool supportsSearchPaging;
  @override
  List<Object?> get values => [
    sourceId,
    displayName,
    supportsDiscover,
    supportsSearchPaging,
  ];
}

/// Source encodes and validates the opaque value, including its query binding.
/// UI only passes it back; it must not log, increment, or persist this value.
final class SearchCursor extends ValueModel {
  SearchCursor({required this.sourceId, required String opaqueValue})
    : opaqueValue = nonBlank(opaqueValue, 'cursor');
  final SourceId sourceId;
  final String opaqueValue;
  @override
  List<Object?> get values => [sourceId, opaqueValue];
}

final class SearchPage {
  SearchPage({
    required this.sourceId,
    required Iterable<NovelSummary> items,
    this.nextCursor,
  }) : items = List.unmodifiable(items) {
    final ids = <NovelKey>{};
    if (this.items.any(
          (item) => item.key.sourceId != sourceId || !ids.add(item.key),
        ) ||
        (nextCursor != null && nextCursor!.sourceId != sourceId)) {
      throw ArgumentError(
        'Search page has inconsistent or duplicate identities',
      );
    }
    if (this.items.isEmpty && nextCursor != null) {
      throw ArgumentError('An empty page must terminate pagination');
    }
  }
  final SourceId sourceId;
  final List<NovelSummary> items;
  final SearchCursor? nextCursor;
}

final class DiscoverSection extends ValueModel {
  DiscoverSection({
    required String label,
    required Iterable<NovelSummary> items,
  }) : label = nonBlank(label, 'label'),
       items = List.unmodifiable(items);
  final String label;
  final List<NovelSummary> items;
  @override
  List<Object?> get values => [label, items];
}

/// All expected failures (including cancellation) are Result failures. No raw
/// transport exceptions cross this boundary. There is no initialize/session API.
abstract interface class NovelSource {
  SourceDescriptor get descriptor;
  Future<Result<List<DiscoverSection>>> discover({
    required CancellationToken cancellation,
  });
  Future<Result<SearchPage>> search(
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  });
  Future<Result<NovelDetail>> getNovelDetail(
    NovelKey key, {
    required CancellationToken cancellation,
  });
  Future<Result<Catalog>> getCatalog(
    NovelKey key, {
    required CancellationToken cancellation,
  });
  Future<Result<ChapterContent>> getChapter(
    ChapterKey key, {
    required CancellationToken cancellation,
  });
}
