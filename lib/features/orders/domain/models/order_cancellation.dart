import 'order_actor.dart';

/// Metadata captured whenever an order is cancelled.
///
/// Kept as a small, separate value object (rather than three loose fields
/// on [OrderModel]) so "was this cancelled" and "why/by whom/when" can
/// never disagree — an order either has one complete [OrderCancellationInfo]
/// or none at all.
class OrderCancellationInfo {
  final String reason;
  final OrderActor actor;
  final DateTime timestamp;

  const OrderCancellationInfo({
    required this.reason,
    required this.actor,
    required this.timestamp,
  });

  OrderCancellationInfo copyWith({
    String? reason,
    OrderActor? actor,
    DateTime? timestamp,
  }) {
    return OrderCancellationInfo(
      reason: reason ?? this.reason,
      actor: actor ?? this.actor,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
