import '../../../orders/domain/models/order_id.dart';
import 'order_closure_lifecycle_status.dart';

/// The order's open/closed/reopened/reclosed history — a new aggregate,
/// deliberately separate from `Order` (`docs/decisions.md` ADR-012): the
/// shared, cross-channel `Order` state machine (Kitchen/Courier/Admin all
/// depend on it) has no business carrying POS-specific closure/reopen
/// semantics, exactly the same reasoning that already kept `PosOrderSession`
/// separate from `Order` in Phase 3 Sprint 3B.
///
/// **Append-only**: never mutated in place — every lifecycle change
/// produces a new [OrderClosure] instance with the same [closureId] and an
/// incremented [revision]; `OrderClosureRepository.save` always appends
/// rather than overwrites, so the full history remains queryable.
class OrderClosure {
  const OrderClosure({
    required this.closureId,
    required this.orderId,
    this.paymentSessionId,
    this.closedAt,
    this.closedByStaffId,
    required this.lifecycleStatus,
    required this.revision,
    this.reopenCount = 0,
  });

  /// Stable across every revision of this record's lifecycle — what
  /// [OrderClosureRepository] queries by.
  final String closureId;

  final OrderId orderId;

  /// The [PaymentSession] currently (or most recently) associated with
  /// this closure — `null` before the first `StartPaymentSession` call.
  final String? paymentSessionId;

  final DateTime? closedAt;
  final String? closedByStaffId;

  final OrderClosureLifecycleStatus lifecycleStatus;

  /// Optimistic-concurrency counter — starts at 1.
  final int revision;

  /// How many times this record has been reopened — `0` until the first
  /// `ReopenClosedOrder` call. `CloseOrderAccount` reads this to decide
  /// whether a closure lands on [OrderClosureLifecycleStatus.closed] (the
  /// first time) or [OrderClosureLifecycleStatus.reclosed] (any time
  /// after).
  final int reopenCount;

  OrderClosure copyWith({
    String? paymentSessionId,
    DateTime? closedAt,
    String? closedByStaffId,
    OrderClosureLifecycleStatus? lifecycleStatus,
    int? revision,
    int? reopenCount,
  }) {
    return OrderClosure(
      closureId: closureId,
      orderId: orderId,
      paymentSessionId: paymentSessionId ?? this.paymentSessionId,
      closedAt: closedAt ?? this.closedAt,
      closedByStaffId: closedByStaffId ?? this.closedByStaffId,
      lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
      revision: revision ?? this.revision,
      reopenCount: reopenCount ?? this.reopenCount,
    );
  }
}
