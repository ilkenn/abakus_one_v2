import '../domain/marketplace_branch_mapping.dart';

abstract interface class MarketplaceBranchMappingRepository {
  Future<void> save(MarketplaceBranchMapping mapping);
  Future<MarketplaceBranchMapping?> findByVirtualRestaurantId(
      String virtualRestaurantId);
}

class InMemoryMarketplaceBranchMappingRepository
    implements MarketplaceBranchMappingRepository {
  final Map<String, MarketplaceBranchMapping> _byVirtualRestaurantId = {};

  @override
  Future<void> save(MarketplaceBranchMapping mapping) async =>
      _byVirtualRestaurantId[mapping.virtualRestaurantId] = mapping;

  @override
  Future<MarketplaceBranchMapping?> findByVirtualRestaurantId(
      String virtualRestaurantId) async {
    return _byVirtualRestaurantId[virtualRestaurantId];
  }
}
