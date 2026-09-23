import '../content_identity.dart';
import 'value_model.dart';

/// A pronunciation attached to a range of base text, in Unicode code points.
final class InlineRuby extends ValueModel {
  InlineRuby({
    required this.start,
    required this.length,
    required String annotation,
  }) : annotation = ContentIdentity.normalizeText(annotation) {
    if (start < 0 ||
        length <= 0 ||
        length > 64 ||
        this.annotation.runes.length > 256 ||
        this.annotation.contains('\n') ||
        this.annotation.trim().isEmpty) {
      throw ArgumentError('Invalid ruby range');
    }
  }

  final int start, length;
  final String annotation;
  int get end => start + length;
  Map<String, Object?> toJson() => {
    'start': start,
    'length': length,
    'annotation': annotation,
  };
  factory InlineRuby.fromJson(Map<String, dynamic> json) => InlineRuby(
    start: json['start'] as int,
    length: json['length'] as int,
    annotation: json['annotation'] as String,
  );
  @override
  List<Object?> get values => [start, length, annotation];
}

void validateInlineRuby(String text, List<InlineRuby> ruby) {
  if (ruby.isEmpty) return;
  final runes = text.runes.toList();
  var end = 0;
  for (final item in ruby) {
    if (item.start < end ||
        item.end > runes.length ||
        runes
            .sublist(item.start, item.end)
            .any((r) => r == 0xfffc || r == 10)) {
      throw ArgumentError('Ruby must reference non-overlapping base text');
    }
    end = item.end;
  }
}
