import '../../../../core/errors/business_rule_violation.dart';

/// A human-readable order number (e.g. a daily-per-branch sequence like
/// `"A-042"`), distinct from [OrderId] (a unique but not necessarily
/// human-friendly identifier).
///
/// **Externally supplied** — same reasoning as [OrderId]. A real
/// sequential-numbering scheme needs server-side coordination (concurrent
/// orders across devices must never collide or skip in a way that
/// confuses staff) that doesn't exist yet; this type only guarantees the
/// value it's given is non-empty. The actual generation strategy is
/// unresolved and out of this sprint's scope.
class OrderNumber {
  factory OrderNumber(String value) {
    if (value.isEmpty) {
      throw const EmptyIdentifierViolation(identifierName: 'OrderNumber');
    }
    return OrderNumber._(value);
  }

  const OrderNumber._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is OrderNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
