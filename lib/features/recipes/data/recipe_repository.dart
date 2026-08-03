import '../domain/recipe.dart';

abstract interface class RecipeRepository {
  Future<void> save(Recipe recipe);
  Future<Recipe?> findById(String id);
  Future<List<Recipe>> findByOrganizationId(String organizationId);
}

class InMemoryRecipeRepository implements RecipeRepository {
  final Map<String, Recipe> _byId = {};

  @override
  Future<void> save(Recipe recipe) async => _byId[recipe.id] = recipe;

  @override
  Future<Recipe?> findById(String id) async => _byId[id];

  @override
  Future<List<Recipe>> findByOrganizationId(String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((r) => r.organizationId == organizationId),
    );
  }
}
