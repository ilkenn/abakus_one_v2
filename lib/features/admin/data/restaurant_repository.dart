import '../domain/organization/restaurant.dart';

abstract interface class RestaurantRepository {
  Future<void> save(Restaurant restaurant);
  Future<Restaurant?> findById(String restaurantId);
  Future<List<Restaurant>> findAll();
  Future<List<Restaurant>> findByOrganizationId(String organizationId);
}

class InMemoryRestaurantRepository implements RestaurantRepository {
  InMemoryRestaurantRepository({List<Restaurant> seed = const []})
      : _byId = {for (final restaurant in seed) restaurant.id: restaurant};

  final Map<String, Restaurant> _byId;

  @override
  Future<void> save(Restaurant restaurant) async =>
      _byId[restaurant.id] = restaurant;

  @override
  Future<Restaurant?> findById(String restaurantId) async =>
      _byId[restaurantId];

  @override
  Future<List<Restaurant>> findAll() async => List.unmodifiable(_byId.values);

  @override
  Future<List<Restaurant>> findByOrganizationId(String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((r) => r.organizationId == organizationId),
    );
  }
}
