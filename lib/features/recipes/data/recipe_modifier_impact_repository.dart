import '../domain/recipe_modifier_impact.dart';

abstract interface class RecipeModifierImpactRepository {
  Future<void> save(RecipeModifierImpact impact);
  Future<List<RecipeModifierImpact>> findByRecipeId(String recipeId);
}

class InMemoryRecipeModifierImpactRepository
    implements RecipeModifierImpactRepository {
  final List<RecipeModifierImpact> _impacts = [];

  @override
  Future<void> save(RecipeModifierImpact impact) async {
    _impacts.add(impact);
  }

  @override
  Future<List<RecipeModifierImpact>> findByRecipeId(String recipeId) async {
    return List.unmodifiable(
      _impacts.where((i) => i.recipeId == recipeId),
    );
  }
}
