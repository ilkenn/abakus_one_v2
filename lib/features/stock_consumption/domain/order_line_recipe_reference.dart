/// What one order line resolved to, in recipe terms, at the moment it
/// was ordered — Phase 7 (`docs/decisions.md` ADR-024). Supplied by
/// the caller of `ConsumeStockForOrder`, never read from a live
/// `Recipe`: [recipeVersionId] must be the exact, historical version
/// that was current when the order was placed — "historical recipe
/// snapshot drives consumption, never current mutable version." This
/// type deliberately does not reference `features/orders`' `OrderLine`
/// — see `ConsumeStockForOrder`'s own doc comment for why no such
/// linkage exists yet in this codebase.
class OrderLineRecipeReference {
  const OrderLineRecipeReference({
    required this.orderLineId,
    required this.recipeId,
    required this.recipeVersionId,
    required this.orderedQuantity,
  });

  final String orderLineId;
  final String recipeId;
  final String recipeVersionId;

  /// How many of this recipe were ordered on this line — each
  /// resolved ingredient quantity is multiplied by this.
  final int orderedQuantity;
}
