import '../domain/standard_ingredient_cost.dart';

abstract interface class StandardIngredientCostRepository {
  Future<void> save(StandardIngredientCost cost);
  Future<StandardIngredientCost?> findByIngredientId(String ingredientId);
}

class InMemoryStandardIngredientCostRepository
    implements StandardIngredientCostRepository {
  final Map<String, StandardIngredientCost> _byIngredientId = {};

  @override
  Future<void> save(StandardIngredientCost cost) async {
    _byIngredientId[cost.ingredientId] = cost;
  }

  @override
  Future<StandardIngredientCost?> findByIngredientId(
      String ingredientId) async {
    return _byIngredientId[ingredientId];
  }
}
