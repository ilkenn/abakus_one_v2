import '../domain/nutrition_calculation_result.dart';

abstract interface class NutritionCalculationResultRepository {
  Future<void> save(NutritionCalculationResult result);
  Future<List<NutritionCalculationResult>> findByRecipeVersionId(
      String recipeVersionId);
}

class InMemoryNutritionCalculationResultRepository
    implements NutritionCalculationResultRepository {
  final List<NutritionCalculationResult> _results = [];

  @override
  Future<void> save(NutritionCalculationResult result) async {
    _results.add(result);
  }

  @override
  Future<List<NutritionCalculationResult>> findByRecipeVersionId(
      String recipeVersionId) async {
    return List.unmodifiable(
      _results.where((r) => r.recipeVersionId == recipeVersionId),
    );
  }
}
