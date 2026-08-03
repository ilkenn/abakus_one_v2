import '../domain/profitability_calculation_result.dart';

abstract interface class ProfitabilityCalculationResultRepository {
  Future<void> save(ProfitabilityCalculationResult result);
  Future<List<ProfitabilityCalculationResult>> findByRecipeId(String recipeId);
}

class InMemoryProfitabilityCalculationResultRepository
    implements ProfitabilityCalculationResultRepository {
  final List<ProfitabilityCalculationResult> _results = [];

  @override
  Future<void> save(ProfitabilityCalculationResult result) async {
    _results.add(result);
  }

  @override
  Future<List<ProfitabilityCalculationResult>> findByRecipeId(
      String recipeId) async {
    return List.unmodifiable(
      _results.where((r) => r.recipeId == recipeId),
    );
  }
}
