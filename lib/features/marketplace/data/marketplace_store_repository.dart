import '../domain/marketplace_store.dart';

abstract interface class MarketplaceStoreRepository {
  Future<void> save(MarketplaceStore store);
  Future<MarketplaceStore?> findById(String id);
  Future<List<MarketplaceStore>> findByMarketplaceAccountId(
      String marketplaceAccountId);
}

class InMemoryMarketplaceStoreRepository implements MarketplaceStoreRepository {
  final Map<String, MarketplaceStore> _byId = {};

  @override
  Future<void> save(MarketplaceStore store) async => _byId[store.id] = store;

  @override
  Future<MarketplaceStore?> findById(String id) async => _byId[id];

  @override
  Future<List<MarketplaceStore>> findByMarketplaceAccountId(
      String marketplaceAccountId) async {
    return List.unmodifiable(
      _byId.values.where((s) => s.marketplaceAccountId == marketplaceAccountId),
    );
  }
}
