/// One recorded visit — Sprint 5D's Visit Passport. Immutable, append-only
/// (mirrors `CourierDispatchQueueEvent`'s shape): a visit is a fact that
/// happened, never edited or deleted, so a passport rebuilt from history
/// can never drift from what actually occurred.
///
/// [orderId] is optional and deliberately loose (`String?`, not a typed
/// `OrderId`) — this feature has no dependency on the orders feature.
/// Wiring a real order-completion event to call `RecordCustomerVisit`
/// automatically is explicitly out of scope this sprint (the same
/// "caller's explicit responsibility" precedent used throughout Sprint 5
/// for order/courier integration) — recording remains a deliberate,
/// caller-initiated action until that wiring is built.
class CustomerVisit {
  const CustomerVisit({
    required this.id,
    required this.customerId,
    required this.branchId,
    this.orderId,
    required this.occurredAt,
  });

  final String id;
  final String customerId;
  final String branchId;
  final String? orderId;
  final DateTime occurredAt;
}
