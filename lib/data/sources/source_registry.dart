import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';

/// Immutable registry. Sources and their transport resources remain caller-owned.
final class SourceRegistry {
  SourceRegistry(Iterable<NovelSource> sources) {
    for (final source in sources) {
      final id = source.descriptor.sourceId;
      if (_sources.containsKey(id)) {
        throw ArgumentError('Duplicate source identity');
      }
      _sources[id] = source;
    }
  }
  final _sources = <SourceId, NovelSource>{};
  NovelSource? operator [](SourceId id) => _sources[id];
  List<SourceDescriptor> get descriptors =>
      List.unmodifiable(_sources.values.map((s) => s.descriptor));
}
