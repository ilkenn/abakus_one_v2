import '../domain/nutrition_reference_entry.dart';

abstract interface class NutritionReferenceEntryRepository {
  Future<void> save(NutritionReferenceEntry entry);
  Future<NutritionReferenceEntry?> findById(String id);
  Future<NutritionReferenceEntry?> findByIngredientId(String ingredientId);
  Future<List<NutritionReferenceEntry>> findByOrganizationId(
      String organizationId);
}

class InMemoryNutritionReferenceEntryRepository
    implements NutritionReferenceEntryRepository {
  final Map<String, NutritionReferenceEntry> _byId = {};

  @override
  Future<void> save(NutritionReferenceEntry entry) async =>
      _byId[entry.id] = entry;

  @override
  Future<NutritionReferenceEntry?> findById(String id) async => _byId[id];

  @override
  Future<NutritionReferenceEntry?> findByIngredientId(
      String ingredientId) async {
    for (final entry in _byId.values) {
      if (entry.ingredientId == ingredientId) return entry;
    }
    return null;
  }

  @override
  Future<List<NutritionReferenceEntry>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((e) => e.organizationId == organizationId),
    );
  }
}
