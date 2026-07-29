/// An action gated by [PosAuthorizationPolicy] — closed-account
/// visibility and every closure-correction action require this check
/// before a use case proceeds.
///
/// The Phase 3 Sprint 3D restaurant-operations values
/// (`reopenTableCheck` onward) reuse this same enum/policy rather than
/// introducing a second authorization contract — `PosAuthorizationPolicy`
/// was already deliberately generic ("an action, an actor, a context"),
/// not payment-specific, so extending it here is additive, not a scope
/// violation (`docs/decisions.md` ADR-013). The Phase 3 Sprint 3E cash-
/// management values (`reviewCashReconciliation` onward) extend it again
/// for the same reason (`docs/decisions.md` ADR-014). The Phase 3
/// Sprint 3F courier-settlement values (`reviewCourierSettlement` onward)
/// extend it once more, same reasoning (`docs/decisions.md` ADR-015).
enum PosAuthorizedAction {
  viewClosedAccount,
  reopenOrder,
  correctPayment,
  voidPayment,
  recloseOrder,
  emergencyChannelClosure,
  reopenTableCheck,
  transferOrMergeAfterPayment,
  cancelAfterPreparation,
  packageCompletionOverride,
  reprintOrDuplicateReceipt,
  operationalCorrection,
  reviewCashReconciliation,
  recordCashAdjustment,
  reviewCourierSettlement,
  recordCourierSettlementAdjustment,
}
