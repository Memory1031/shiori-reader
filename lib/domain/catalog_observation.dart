import 'contracts/loading.dart';
import 'models/novel.dart';

/// Fetch time belongs to the data, not to the cache read or callback arrival.
/// Equal-time conflicting cache snapshots cannot supersede a remote observation.
/// Chapter counts are deliberately irrelevant: newer catalogs may remove/reorder.
bool acceptsCatalogObservation(
  LoadResult<Catalog> candidate,
  LoadResult<Catalog>? current,
) {
  if (current == null) return true;
  final age = candidate.fetchedAt.compareTo(current.fetchedAt);
  if (age != 0) return age > 0;
  if (candidate.value.revision == current.value.revision) return false;
  return candidate.origin == LoadOrigin.remote &&
      current.origin != LoadOrigin.remote;
}
