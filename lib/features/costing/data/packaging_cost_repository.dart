import '../domain/packaging_cost.dart';

abstract interface class PackagingCostRepository {
  Future<void> save(PackagingCost cost);
  Future<List<PackagingCost>> findByOrganizationId(String organizationId);
}

class InMemoryPackagingCostRepository implements PackagingCostRepository {
  final Map<String, PackagingCost> _byId = {};

  @override
  Future<void> save(PackagingCost cost) async => _byId[cost.id] = cost;

  @override
  Future<List<PackagingCost>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((c) => c.organizationId == organizationId),
    );
  }
}
