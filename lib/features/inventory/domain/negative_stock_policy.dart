/// How a `StockMovement` that would take on-hand quantity below zero is
/// handled — "negative stock policy must be configurable" (Phase 7,
/// `docs/decisions.md` ADR-024).
enum NegativeStockPolicy {
  /// The movement is rejected — `NegativeStockNotAllowedViolation`.
  forbid,

  /// The movement is recorded, but the resulting `BranchStock` is
  /// flagged — no violation thrown, no code today reads the flag
  /// further (an honest, foundation-only warning surface).
  warn,

  /// The movement is always recorded, on-hand may go negative freely.
  allow,
}
