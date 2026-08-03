import '../domain/allergen_type.dart';
import '../domain/ingredient_allergen_declaration.dart';

abstract interface class IngredientAllergenDeclarationRepository {
  Future<void> save(IngredientAllergenDeclaration declaration);
  Future<IngredientAllergenDeclaration?> findById(String id);
  Future<IngredientAllergenDeclaration?> findByIngredientAndAllergen(
      String ingredientId, AllergenType allergenType);
  Future<List<IngredientAllergenDeclaration>> findByIngredientId(
      String ingredientId);
  Future<List<IngredientAllergenDeclaration>> findByOrganizationId(
      String organizationId);
}

class InMemoryIngredientAllergenDeclarationRepository
    implements IngredientAllergenDeclarationRepository {
  final Map<String, IngredientAllergenDeclaration> _byId = {};

  @override
  Future<void> save(IngredientAllergenDeclaration declaration) async =>
      _byId[declaration.id] = declaration;

  @override
  Future<IngredientAllergenDeclaration?> findById(String id) async => _byId[id];

  @override
  Future<IngredientAllergenDeclaration?> findByIngredientAndAllergen(
      String ingredientId, AllergenType allergenType) async {
    for (final declaration in _byId.values) {
      if (declaration.ingredientId == ingredientId &&
          declaration.allergenType == allergenType) {
        return declaration;
      }
    }
    return null;
  }

  @override
  Future<List<IngredientAllergenDeclaration>> findByIngredientId(
      String ingredientId) async {
    return List.unmodifiable(
      _byId.values.where((d) => d.ingredientId == ingredientId),
    );
  }

  @override
  Future<List<IngredientAllergenDeclaration>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((d) => d.organizationId == organizationId),
    );
  }
}
