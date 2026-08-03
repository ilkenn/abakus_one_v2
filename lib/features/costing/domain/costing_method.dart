/// How an ingredient's unit cost is resolved from its recorded
/// [PurchasePrice] history — Phase 7 (`docs/decisions.md` ADR-024).
/// Each value has a corresponding `IngredientCostResolver` strategy
/// implementation — "costing methods via strategy contracts."
enum CostingMethod {
  /// The single most recent [PurchasePrice] for the ingredient.
  latestPurchase,

  /// A quantity-weighted average across every recorded [PurchasePrice]
  /// for the ingredient.
  weightedAverage,

  /// A manually-set [StandardIngredientCost], independent of purchase
  /// history (a target/planned cost rather than an observed one).
  standard,
}
