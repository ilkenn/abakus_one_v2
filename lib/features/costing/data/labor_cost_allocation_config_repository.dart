import '../domain/labor_cost_allocation_config.dart';

abstract interface class LaborCostAllocationConfigRepository {
  Future<void> save(LaborCostAllocationConfig config);
  Future<List<LaborCostAllocationConfig>> findByBranchId(String branchId);
}

class InMemoryLaborCostAllocationConfigRepository
    implements LaborCostAllocationConfigRepository {
  final List<LaborCostAllocationConfig> _configs = [];

  @override
  Future<void> save(LaborCostAllocationConfig config) async {
    _configs.add(config);
  }

  @override
  Future<List<LaborCostAllocationConfig>> findByBranchId(
      String branchId) async {
    return List.unmodifiable(
      _configs.where((c) => c.branchId == branchId),
    );
  }
}
