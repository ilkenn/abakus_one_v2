import '../domain/cost_calculation_result.dart';

abstract interface class CostCalculationResultRepository {
  Future<void> save(CostCalculationResult result);
  Future<List<CostCalculationResult>> findByRecipeVersionId(
      String recipeVersionId);
}

class InMemoryCostCalculationResultRepository
    implements CostCalculationResultRepository {
  final List<CostCalculationResult> _results = [];

  @override
  Future<void> save(CostCalculationResult result) async {
    _results.add(result);
  }

  @override
  Future<List<CostCalculationResult>> findByRecipeVersionId(
      String recipeVersionId) async {
    return List.unmodifiable(
      _results.where((r) => r.recipeVersionId == recipeVersionId),
    );
  }
}
