import '../content_identity.dart';
import 'identity.dart';
import 'value_model.dart';

/// A book-scoped family, with its available font faces in source order.
final class EmbeddedFontFamily extends ValueModel {
  EmbeddedFontFamily(Iterable<MediaRef> sources)
    : sources = List.unmodifiable(sources) {
    if (this.sources.isEmpty ||
        this.sources.length > 8 ||
        this.sources.any((s) => s.sourceId.value != 'local')) {
      throw ArgumentError('Invalid embedded font family');
    }
  }
  final List<MediaRef> sources;
  late final String familyName =
      'ShioriEpub_${ContentIdentity.digest('epub-font', sources.map((s) => s.identityFields).toList())}';
  Map<String, Object?> toJson() => {
    'sources': sources.map((s) => s.toJson()).toList(),
  };
  factory EmbeddedFontFamily.fromJson(Map<String, dynamic> j) =>
      EmbeddedFontFamily(
        (j['sources'] as List).map(
          (s) => MediaRef.fromJson(s as Map<String, dynamic>),
        ),
      );
  @override
  List<Object?> get values => [sources];
}
