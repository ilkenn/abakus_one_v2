import '../domain/organization/branch.dart';

abstract interface class BranchRepository {
  Future<void> save(Branch branch);
  Future<Branch?> findById(String branchId);
  Future<List<Branch>> findAll();
  Future<List<Branch>> findByRestaurantId(String restaurantId);
}

class InMemoryBranchRepository implements BranchRepository {
  InMemoryBranchRepository({List<Branch> seed = const []})
      : _byId = {for (final branch in seed) branch.id: branch};

  final Map<String, Branch> _byId;

  @override
  Future<void> save(Branch branch) async => _byId[branch.id] = branch;

  @override
  Future<Branch?> findById(String branchId) async => _byId[branchId];

  @override
  Future<List<Branch>> findAll() async => List.unmodifiable(_byId.values);

  @override
  Future<List<Branch>> findByRestaurantId(String restaurantId) async {
    return List.unmodifiable(
      _byId.values.where((b) => b.restaurantId == restaurantId),
    );
  }
}
