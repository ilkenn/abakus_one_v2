import '../domain/visits/customer_visit.dart';

/// Append-only storage for [CustomerVisit] — no update or delete method
/// exists at all, matching every other append-only repository in this
/// codebase (`CourierDispatchQueueEventRepository`, etc.).
abstract interface class CustomerVisitRepository {
  Future<void> append(CustomerVisit visit);
  Future<List<CustomerVisit>> findByCustomerId(String customerId);

  /// The visit already recorded for [orderId], if any — **Sprint 5E**'s
  /// idempotency guard: "the same order must never create multiple
  /// visits" (`docs/decisions.md` ADR-022). `null` for an `orderId` no
  /// visit references, including every visit recorded with no order
  /// reference at all (`CustomerVisit.orderId == null`).
  Future<CustomerVisit?> findByOrderId(String orderId);
}

class InMemoryCustomerVisitRepository implements CustomerVisitRepository {
  final List<CustomerVisit> _visits = [];

  @override
  Future<void> append(CustomerVisit visit) async {
    _visits.add(visit);
  }

  @override
  Future<List<CustomerVisit>> findByCustomerId(String customerId) async {
    return List.unmodifiable(
      _visits.where((v) => v.customerId == customerId),
    );
  }

  @override
  Future<CustomerVisit?> findByOrderId(String orderId) async {
    for (final visit in _visits) {
      if (visit.orderId == orderId) return visit;
    }
    return null;
  }
}
