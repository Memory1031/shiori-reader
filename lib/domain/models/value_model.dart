import '../content_identity.dart';

/// Runtime equality/hashCode is for in-process collections only.
/// Persistent identities MUST use ContentIdentity instead.
abstract class ValueModel {
  const ValueModel();
  List<Object?> get values;

  static bool _equal(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equal(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static int _hash(Object? value) =>
      value is List ? Object.hashAll(value.map(_hash)) : value.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValueModel &&
          runtimeType == other.runtimeType &&
          _equal(values, other.values);

  @override
  int get hashCode => Object.hash(runtimeType, _hash(values));
}

String nonBlank(String value, String field) {
  ContentIdentity.validateUnicode(value);
  if (value.trim().isEmpty) throw ArgumentError('$field must not be blank');
  return value; // Opaque identifiers are never trimmed or interpreted.
}

int nonNegative(int value, String field) {
  if (value < 0) throw ArgumentError('$field must be nonnegative');
  return value;
}

double finiteRange(double value, double min, double max, String field) {
  if (!value.isFinite || value < min || value > max) {
    throw ArgumentError('$field is outside its finite range');
  }
  return value == 0 ? 0 : value;
}
