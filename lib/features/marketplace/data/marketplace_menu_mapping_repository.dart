import '../domain/marketplace_menu_mapping.dart';

abstract interface class MarketplaceMenuMappingRepository {
  Future<void> save(MarketplaceMenuMapping mapping);
  Future<List<MarketplaceMenuMapping>> findByVirtualRestaurantId(
      String virtualRestaurantId);
  Future<MarketplaceMenuMapping?> findByVirtualRestaurantAndProduct(
    String virtualRestaurantId,
    String internalMenuProductId,
  );
}

class InMemoryMarketplaceMenuMappingRepository
    implements MarketplaceMenuMappingRepository {
  final List<MarketplaceMenuMapping> _mappings = [];

  @override
  Future<void> save(MarketplaceMenuMapping mapping) async {
    _mappings.removeWhere((m) => m.id == mapping.id);
    _mappings.add(mapping);
  }

  @override
  Future<List<MarketplaceMenuMapping>> findByVirtualRestaurantId(
      String virtualRestaurantId) async {
    return List.unmodifiable(
      _mappings.where((m) => m.virtualRestaurantId == virtualRestaurantId),
    );
  }

  @override
  Future<MarketplaceMenuMapping?> findByVirtualRestaurantAndProduct(
    String virtualRestaurantId,
    String internalMenuProductId,
  ) async {
    for (final mapping in _mappings) {
      if (mapping.virtualRestaurantId == virtualRestaurantId &&
          mapping.internalMenuProductId == internalMenuProductId) {
        return mapping;
      }
    }
    return null;
  }
}
