import '../domain/marketplace_account.dart';

abstract interface class MarketplaceAccountRepository {
  Future<void> save(MarketplaceAccount account);
  Future<MarketplaceAccount?> findById(String id);
  Future<List<MarketplaceAccount>> findByOrganizationId(String organizationId);
}

class InMemoryMarketplaceAccountRepository
    implements MarketplaceAccountRepository {
  final Map<String, MarketplaceAccount> _byId = {};

  @override
  Future<void> save(MarketplaceAccount account) async =>
      _byId[account.id] = account;

  @override
  Future<MarketplaceAccount?> findById(String id) async => _byId[id];

  @override
  Future<List<MarketplaceAccount>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((a) => a.organizationId == organizationId),
    );
  }
}
