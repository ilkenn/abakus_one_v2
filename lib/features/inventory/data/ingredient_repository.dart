import '../domain/ingredient.dart';

abstract interface class IngredientRepository {
  Future<void> save(Ingredient ingredient);
  Future<Ingredient?> findById(String id);
  Future<List<Ingredient>> findByOrganizationId(String organizationId);
}

class InMemoryIngredientRepository implements IngredientRepository {
  final Map<String, Ingredient> _byId = {};

  @override
  Future<void> save(Ingredient ingredient) async =>
      _byId[ingredient.id] = ingredient;

  @override
  Future<Ingredient?> findById(String id) async => _byId[id];

  @override
  Future<List<Ingredient>> findByOrganizationId(String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((i) => i.organizationId == organizationId),
    );
  }
}
