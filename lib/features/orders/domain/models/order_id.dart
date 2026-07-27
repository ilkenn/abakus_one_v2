import '../../../../core/errors/business_rule_violation.dart';

/// A unique order identifier.
///
/// **Externally supplied** — approved architecture decision. No ID-
/// generation mechanism exists in this codebase (every id anywhere today
/// is a literal string in mock data; no `uuid` package or similar is a
/// dependency), and this sprint doesn't add one. Generating a real,
/// collision-safe id is the calling code's (eventually a backend's)
/// responsibility; [OrderId] only guarantees the value it's given is
/// non-empty.
class OrderId {
  factory OrderId(String value) {
    if (value.isEmpty) {
      throw const EmptyIdentifierViolation(identifierName: 'OrderId');
    }
    return OrderId._(value);
  }

  const OrderId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is OrderId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
