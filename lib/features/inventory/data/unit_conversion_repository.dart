import '../domain/unit_conversion.dart';

abstract interface class UnitConversionRepository {
  Future<void> save(UnitConversion conversion);
  Future<List<UnitConversion>> findByIngredientId(String ingredientId);
}

class InMemoryUnitConversionRepository implements UnitConversionRepository {
  final Map<String, UnitConversion> _byId = {};

  @override
  Future<void> save(UnitConversion conversion) async =>
      _byId[conversion.id] = conversion;

  @override
  Future<List<UnitConversion>> findByIngredientId(String ingredientId) async {
    return List.unmodifiable(
      _byId.values.where((c) => c.ingredientId == ingredientId),
    );
  }
}
