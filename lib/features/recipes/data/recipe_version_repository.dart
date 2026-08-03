import '../domain/recipe_version.dart';

abstract interface class RecipeVersionRepository {
  Future<void> save(RecipeVersion version);
  Future<RecipeVersion?> findById(String id);
  Future<List<RecipeVersion>> findByRecipeId(String recipeId);
}

class InMemoryRecipeVersionRepository implements RecipeVersionRepository {
  final Map<String, RecipeVersion> _byId = {};

  @override
  Future<void> save(RecipeVersion version) async => _byId[version.id] = version;

  @override
  Future<RecipeVersion?> findById(String id) async => _byId[id];

  @override
  Future<List<RecipeVersion>> findByRecipeId(String recipeId) async {
    return List.unmodifiable(
      _byId.values.where((v) => v.recipeId == recipeId),
    );
  }
}
