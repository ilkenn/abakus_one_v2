/// When, in an order's lifecycle, its ingredients are deducted from
/// stock — Phase 7 (`docs/decisions.md` ADR-024). Configurable per
/// branch+channel via [StockConsumptionChannelPolicy] — "timing
/// policies (order accepted/preparation started/order completed/
/// configurable channel policy)."
enum StockConsumptionTimingPolicy {
  orderAccepted,
  preparationStarted,
  orderCompleted,
}
