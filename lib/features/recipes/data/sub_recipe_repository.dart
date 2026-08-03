import '../domain/sub_recipe.dart';

abstract interface class SubRecipeRepository {
  Future<void> save(SubRecipe subRecipe);
  Future<SubRecipe?> findById(String id);
  Future<List<SubRecipe>> findByOrganizationId(String organizationId);
}

class InMemorySubRecipeRepository implements SubRecipeRepository {
  final Map<String, SubRecipe> _byId = {};

  @override
  Future<void> save(SubRecipe subRecipe) async =>
      _byId[subRecipe.id] = subRecipe;

  @override
  Future<SubRecipe?> findById(String id) async => _byId[id];

  @override
  Future<List<SubRecipe>> findByOrganizationId(String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((s) => s.organizationId == organizationId),
    );
  }
}
