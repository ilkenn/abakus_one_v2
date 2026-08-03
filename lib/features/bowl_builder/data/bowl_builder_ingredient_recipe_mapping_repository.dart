import '../domain/models/bowl_builder_ingredient_recipe_mapping.dart';

abstract interface class BowlBuilderIngredientRecipeMappingRepository {
  Future<void> save(BowlBuilderIngredientRecipeMapping mapping);
  Future<BowlBuilderIngredientRecipeMapping?> findByBowlBuilderIngredientId(
      String bowlBuilderIngredientId);
  Future<List<BowlBuilderIngredientRecipeMapping>> findByOrganizationId(
      String organizationId);
}

class InMemoryBowlBuilderIngredientRecipeMappingRepository
    implements BowlBuilderIngredientRecipeMappingRepository {
  final Map<String, BowlBuilderIngredientRecipeMapping> _byBowlIngredientId =
      {};

  @override
  Future<void> save(BowlBuilderIngredientRecipeMapping mapping) async {
    _byBowlIngredientId[mapping.bowlBuilderIngredientId] = mapping;
  }

  @override
  Future<BowlBuilderIngredientRecipeMapping?> findByBowlBuilderIngredientId(
      String bowlBuilderIngredientId) async {
    return _byBowlIngredientId[bowlBuilderIngredientId];
  }

  @override
  Future<List<BowlBuilderIngredientRecipeMapping>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _byBowlIngredientId.values
          .where((m) => m.organizationId == organizationId),
    );
  }
}
