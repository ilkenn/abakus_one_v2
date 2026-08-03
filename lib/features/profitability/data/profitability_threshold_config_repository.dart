import '../domain/profitability_threshold_config.dart';

abstract interface class ProfitabilityThresholdConfigRepository {
  Future<void> save(ProfitabilityThresholdConfig config);
  Future<ProfitabilityThresholdConfig?> findByBranchId(String branchId);
}

class InMemoryProfitabilityThresholdConfigRepository
    implements ProfitabilityThresholdConfigRepository {
  final Map<String, ProfitabilityThresholdConfig> _byBranchId = {};

  @override
  Future<void> save(ProfitabilityThresholdConfig config) async {
    _byBranchId[config.branchId] = config;
  }

  @override
  Future<ProfitabilityThresholdConfig?> findByBranchId(String branchId) async {
    return _byBranchId[branchId];
  }
}
