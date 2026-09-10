/// AP-6 Sprint 3 — a [ConsortiumDeliverySettlement]'s own reconciliation
/// standing. Deliberately a minimal 2-value enum this sprint — a full
/// approval/dispute workflow (mirroring `CourierSettlementStatus`'s own
/// richer states in `lib/features/pos/domain/courier_settlement/`) is not
/// requested and would be scope creep; this sprint only needs enough to
/// distinguish "owed, not yet reconciled" from "reconciled."
enum ConsortiumSettlementStatus {
  /// Created automatically when the consortium order it belongs to reaches
  /// completion — not yet reconciled with the external merchant.
  pending,

  /// Reconciled — no real UI/callable flips this to `settled` yet this
  /// sprint (the end-of-day reconciliation report is out of scope, see
  /// `registerConsortiumOrder.ts`'s own doc comment); the value exists so
  /// the model is forward-compatible with that future work rather than
  /// needing a schema change later.
  settled,
}
