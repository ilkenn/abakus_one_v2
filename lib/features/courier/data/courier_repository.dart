import '../domain/identity/courier.dart';

/// Storage for [Courier] records — mutable, mirrors `CashDrawerRepository`.
abstract interface class CourierRepository {
  Future<void> save(Courier courier);
  Future<Courier?> findById(String courierId);

  /// Branch-scoped — never an unscoped "all couriers" query, so branch
  /// data never leaks across branches.
  Future<List<Courier>> findByBranchId(String branchId);
}

class InMemoryCourierRepository implements CourierRepository {
  final Map<String, Courier> _byId = {};

  @override
  Future<void> save(Courier courier) async => _byId[courier.id] = courier;

  @override
  Future<Courier?> findById(String courierId) async => _byId[courierId];

  @override
  Future<List<Courier>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _byId.values.where((c) => c.eligibleForBranch(branchId)),
    );
  }
}
