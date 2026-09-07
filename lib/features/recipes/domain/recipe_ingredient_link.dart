import '../../inventory/domain/quantity.dart';

/// One already-flattened stock requirement carried directly on a
/// [RecipeIngredientLink] — the wire-level equivalent of
/// [RecipeIngredientSnapshot]'s "flattened, resolved ingredient line for a
/// fixed recipe version" concept, but supplied directly by the caller of
/// `setRecipeIngredientLink` rather than computed by
/// `ResolveRecipeIngredientSnapshot`. **Why embedded, not computed
/// server-side**: `RecipeVersion`/`SubRecipe`/`SubRecipeVersion` (the
/// nested composition `RecipeLineFlattener` would normally expand) are
/// still entirely Dart in-memory — no real Firestore document exists for
/// a server-side function to read and flatten. Embedding the already-
/// flattened result is what makes server-authoritative consumption
/// possible at all this sprint; full nested sub-recipe recalculation
/// server-side is out of scope until `recipes`/`recipeVersions` get a
/// real Firestore writer of their own.
///
/// **[inventoryItemId], not `ingredientId`**: `Ingredient`/`InventoryItem`
/// (the catalog/tracking split `ConsumeStockForOrder` uses) has no real
/// Firestore data either yet — the stock ledger (`branchStock`/
/// `stockMovements`) keys off `inventoryItemId` directly, so this line
/// references that id straight away rather than an ingredient catalog
/// entry a server-side lookup couldn't resolve anyway.
class RecipeIngredientLinkLine {
  const RecipeIngredientLinkLine({
    required this.inventoryItemId,
    required this.quantity,
  });

  final String inventoryItemId;
  final Quantity quantity;
}

/// The binding a `MenuProduct`/Bowl Builder composition needs to trigger
/// server-authoritative stock consumption on acceptance — AP-5 Sprint 2,
/// closing the gap `ConsumeStockForOrder`'s own doc comment disclosed
/// honestly: "no menu product currently references a recipe id at all."
///
/// **Deliberate per-product opt-in, never an error when absent**
/// (`docs/kds_printer_stock_architecture.md` §15): a product with no
/// [RecipeIngredientLink] simply never triggers consumption — this lets
/// stock tracking roll out incrementally, product by product.
///
/// [recipeVersionId] stays as an audit/traceability reference to which
/// Dart-side recipe version [ingredients] was resolved from; [ingredients]
/// itself — not a live re-flattening of that version — is what
/// server-side consumption actually deducts against (see
/// [RecipeIngredientLinkLine]'s own doc comment for why).
///
/// **Organization-scoped** (mirrors `Recipe`'s own scope exactly — no
/// `branchId`, a product's recipe binding doesn't vary per branch).
/// A correction is a new upsert with an incremented [revision] — a
/// *current binding* record, not itself a separate history collection
/// (the historical guarantee for a past order lives in that order's own
/// stock-consumption record, which snapshots [ingredients] at accept
/// time, never re-reads this link later).
class RecipeIngredientLink {
  const RecipeIngredientLink({
    required this.id,
    required this.organizationId,
    required this.productId,
    required this.recipeVersionId,
    required this.ingredients,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String productId;
  final String recipeVersionId;
  final List<RecipeIngredientLinkLine> ingredients;
  final DateTime createdAt;
  final int revision;

  RecipeIngredientLink copyWith({
    required String recipeVersionId,
    required List<RecipeIngredientLinkLine> ingredients,
    required int revision,
  }) {
    return RecipeIngredientLink(
      id: id,
      organizationId: organizationId,
      productId: productId,
      recipeVersionId: recipeVersionId,
      ingredients: ingredients,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
