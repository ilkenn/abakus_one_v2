import '../domain/visits/customer_visit.dart';

/// Append-only storage for [CustomerVisit] — no update or delete method
/// exists at all, matching every other append-only repository in this
/// codebase (`CourierDispatchQueueEventRepository`, etc.).
abstract interface class CustomerVisitRepository {
  Future<void> append(CustomerVisit visit);
  Future<List<CustomerVisit>> findByCustomerId(String customerId);
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
}
