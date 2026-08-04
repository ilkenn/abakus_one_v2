import '../domain/virtual_restaurant.dart';

abstract interface class VirtualRestaurantRepository {
  Future<void> save(VirtualRestaurant restaurant);
  Future<VirtualRestaurant?> findById(String id);
  Future<List<VirtualRestaurant>> findByMarketplaceStoreId(
      String marketplaceStoreId);
}

class InMemoryVirtualRestaurantRepository
    implements VirtualRestaurantRepository {
  final Map<String, VirtualRestaurant> _byId = {};

  @override
  Future<void> save(VirtualRestaurant restaurant) async =>
      _byId[restaurant.id] = restaurant;

  @override
  Future<VirtualRestaurant?> findById(String id) async => _byId[id];

  @override
  Future<List<VirtualRestaurant>> findByMarketplaceStoreId(
      String marketplaceStoreId) async {
    return List.unmodifiable(
      _byId.values.where((r) => r.marketplaceStoreId == marketplaceStoreId),
    );
  }
}
