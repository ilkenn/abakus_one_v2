import '../domain/overhead_allocation_config.dart';

abstract interface class OverheadAllocationConfigRepository {
  Future<void> save(OverheadAllocationConfig config);
  Future<List<OverheadAllocationConfig>> findByBranchId(String branchId);
}

class InMemoryOverheadAllocationConfigRepository
    implements OverheadAllocationConfigRepository {
  final List<OverheadAllocationConfig> _configs = [];

  @override
  Future<void> save(OverheadAllocationConfig config) async {
    _configs.add(config);
  }

  @override
  Future<List<OverheadAllocationConfig>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _configs.where((c) => c.branchId == branchId),
    );
  }
}
