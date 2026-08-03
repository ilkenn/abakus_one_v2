import '../domain/recipe_ingredient_snapshot.dart';

abstract interface class RecipeIngredientSnapshotRepository {
  Future<void> save(RecipeIngredientSnapshot snapshot);
  Future<List<RecipeIngredientSnapshot>> findByRecipeVersionId(
      String recipeVersionId);
}

class InMemoryRecipeIngredientSnapshotRepository
    implements RecipeIngredientSnapshotRepository {
  final List<RecipeIngredientSnapshot> _snapshots = [];

  @override
  Future<void> save(RecipeIngredientSnapshot snapshot) async {
    _snapshots.add(snapshot);
  }

  @override
  Future<List<RecipeIngredientSnapshot>> findByRecipeVersionId(
      String recipeVersionId) async {
    return List.unmodifiable(
      _snapshots.where((s) => s.recipeVersionId == recipeVersionId),
    );
  }
}
