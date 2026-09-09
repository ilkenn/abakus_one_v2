import 'order_status.dart';

/// When an order reached each tracked lifecycle stage.
///
/// Only the 7 stages explicitly required by this phase are tracked
/// (`created`, `confirmed`, `preparing`, `ready`, `served`, `completed`,
/// `cancelled`). `pendingConfirmation`, `outForDelivery`, `rejected`, and
/// `refunded` are deliberately not given their own timestamp field here —
/// see `docs/order_lifecycle_architecture.md` for why, and revisit if a
/// concrete reporting need for them shows up.
class OrderTimestamps {
  final DateTime created;
  final DateTime? confirmed;
  final DateTime? preparing;
  final DateTime? ready;
  final DateTime? served;
  final DateTime? completed;
  final DateTime? cancelled;

  const OrderTimestamps({
    required this.created,
    this.confirmed,
    this.preparing,
    this.ready,
    this.served,
    this.completed,
    this.cancelled,
  });

  /// Returns a copy with the timestamp for [status] set to [at], if
  /// [status] is one of the 7 tracked stages. Any other status leaves this
  /// instance unchanged.
  OrderTimestamps recordedAt(OrderStatus status, DateTime at) {
    switch (status) {
      case OrderStatus.confirmed:
        return copyWith(confirmed: at);
      case OrderStatus.preparing:
        return copyWith(preparing: at);
      case OrderStatus.ready:
        return copyWith(ready: at);
      case OrderStatus.served:
        return copyWith(served: at);
      case OrderStatus.completed:
        return copyWith(completed: at);
      case OrderStatus.cancelled:
        return copyWith(cancelled: at);
      case OrderStatus.created:
      case OrderStatus.pendingConfirmation:
      case OrderStatus.outForDelivery:
      case OrderStatus.rejected:
      case OrderStatus.refunded:
      // AP-6 Sprint 1 — not one of the 7 tracked stages, same bucket as
      // pendingConfirmation: a scheduled order has no dedicated timestamp
      // slot of its own (its eventual confirmed/preparing/... timestamps
      // are recorded normally once takeawayOperationsSweep.ts promotes it).
      case OrderStatus.scheduled:
        return this;
    }
  }

  OrderTimestamps copyWith({
    DateTime? created,
    DateTime? confirmed,
    DateTime? preparing,
    DateTime? ready,
    DateTime? served,
    DateTime? completed,
    DateTime? cancelled,
  }) {
    return OrderTimestamps(
      created: created ?? this.created,
      confirmed: confirmed ?? this.confirmed,
      preparing: preparing ?? this.preparing,
      ready: ready ?? this.ready,
      served: served ?? this.served,
      completed: completed ?? this.completed,
      cancelled: cancelled ?? this.cancelled,
    );
  }
}
