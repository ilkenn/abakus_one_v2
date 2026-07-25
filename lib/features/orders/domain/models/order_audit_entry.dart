import 'order_actor.dart';
import 'order_status.dart';

/// What kind of change an [OrderAuditEntry] records.
enum OrderAuditChangeType { statusChange, priceChange, manualAdjustment }

/// A single, immutable record of a change made to an order.
///
/// This is a lightweight, in-memory audit shape only — there is no
/// persistence layer yet (see `docs/order_lifecycle_architecture.md` §7).
/// It exists now so that every place that will eventually mutate an order
/// (status transitions, price/discount adjustments, manual staff edits)
/// has one consistent record shape to append to from day one, rather than
/// each future feature inventing its own ad-hoc log entry.
class OrderAuditEntry {
  final String id;
  final OrderAuditChangeType type;
  final String description;
  final OrderActor actor;
  final DateTime timestamp;
  final String? previousValue;
  final String? newValue;

  const OrderAuditEntry({
    required this.id,
    required this.type,
    required this.description,
    required this.actor,
    required this.timestamp,
    this.previousValue,
    this.newValue,
  });

  /// Convenience factory for the most common audit entry: a status
  /// transition. [from]/[to] are recorded both in the human-readable
  /// [description] and as raw enum names in [previousValue]/[newValue].
  factory OrderAuditEntry.statusChange({
    required String id,
    required OrderStatus from,
    required OrderStatus to,
    required OrderActor actor,
    required DateTime at,
  }) {
    return OrderAuditEntry(
      id: id,
      type: OrderAuditChangeType.statusChange,
      description: 'Status changed from ${from.name} to ${to.name}',
      actor: actor,
      timestamp: at,
      previousValue: from.name,
      newValue: to.name,
    );
  }

  OrderAuditEntry copyWith({
    String? id,
    OrderAuditChangeType? type,
    String? description,
    OrderActor? actor,
    DateTime? timestamp,
    String? previousValue,
    String? newValue,
  }) {
    return OrderAuditEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      description: description ?? this.description,
      actor: actor ?? this.actor,
      timestamp: timestamp ?? this.timestamp,
      previousValue: previousValue ?? this.previousValue,
      newValue: newValue ?? this.newValue,
    );
  }
}
