import '../domain/recipe_ingredient_link.dart';

abstract interface class RecipeIngredientLinkRepository {
  Future<void> save(RecipeIngredientLink link);
  Future<RecipeIngredientLink?> findById(String id);

  /// The active link for [productId], if any — what stock consumption
  /// resolves against; `null` means the product deliberately has no
  /// recipe binding yet (never an error, per the class's own doc comment).
  Future<RecipeIngredientLink?> findByProductId(String productId);
}

class InMemoryRecipeIngredientLinkRepository
    implements RecipeIngredientLinkRepository {
  final Map<String, RecipeIngredientLink> _byId = {};

  @override
  Future<void> save(RecipeIngredientLink link) async => _byId[link.id] = link;

  @override
  Future<RecipeIngredientLink?> findById(String id) async => _byId[id];

  @override
  Future<RecipeIngredientLink?> findByProductId(String productId) async {
    for (final link in _byId.values) {
      if (link.productId == productId) return link;
    }
    return null;
  }
}
