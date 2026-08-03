/// An append-only ledger entry recording that one order line's stock
/// was consumed (or, once reversed, un-consumed) — Phase 7
/// (`docs/decisions.md` ADR-024). Keyed by [idempotencyKey] (derived
/// deterministically from `orderId`+`orderLineId`) — `ConsumeStockForOrder`
/// checks for an existing record before doing any work, so retrying
/// the same order-line consumption is always a safe no-op — "no
/// double deduction."
///
/// [ingredientIdempotencyKeys] lists the exact per-ingredient
/// `StockMovement.idempotencyKey`s this record produced —
/// `ReverseStockConsumption` uses them to find and reverse the exact
/// movements, rather than re-deriving quantities from a
/// possibly-since-changed recipe.
class StockConsumptionRecord {
  const StockConsumptionRecord({
    required this.id,
    required this.idempotencyKey,
    required this.orderId,
    required this.orderLineId,
    required this.branchId,
    required this.locationId,
    required this.recipeId,
    required this.recipeVersionId,
    required this.ingredientIdempotencyKeys,
    required this.consumedAt,
    this.reversedAt,
  });

  final String id;
  final String idempotencyKey;
  final String orderId;
  final String orderLineId;
  final String branchId;
  final String locationId;
  final String recipeId;
  final String recipeVersionId;
  final List<String> ingredientIdempotencyKeys;
  final DateTime consumedAt;
  final DateTime? reversedAt;

  StockConsumptionRecord copyWith({required DateTime reversedAt}) {
    return StockConsumptionRecord(
      id: id,
      idempotencyKey: idempotencyKey,
      orderId: orderId,
      orderLineId: orderLineId,
      branchId: branchId,
      locationId: locationId,
      recipeId: recipeId,
      recipeVersionId: recipeVersionId,
      ingredientIdempotencyKeys: ingredientIdempotencyKeys,
      consumedAt: consumedAt,
      reversedAt: reversedAt,
    );
  }
}
