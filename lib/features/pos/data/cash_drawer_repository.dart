import '../domain/cash/cash_drawer.dart';

/// Storage for [CashDrawer] records — mutable, like
/// `RestaurantTableRepository`: a drawer's current registry shape is what
/// matters, not a revision history of it.
abstract interface class CashDrawerRepository {
  Future<void> save(CashDrawer drawer);

  Future<CashDrawer?> findById(String drawerId);

  Future<List<CashDrawer>> findByBranchId(String branchId);
}

/// In-memory [CashDrawerRepository] — the only implementation this
/// sprint.
class InMemoryCashDrawerRepository implements CashDrawerRepository {
  final Map<String, CashDrawer> _drawersById = {};

  @override
  Future<void> save(CashDrawer drawer) async {
    _drawersById[drawer.id] = drawer;
  }

  @override
  Future<CashDrawer?> findById(String drawerId) async {
    return _drawersById[drawerId];
  }

  @override
  Future<List<CashDrawer>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _drawersById.values.where((drawer) => drawer.branchId == branchId),
    );
  }
}
