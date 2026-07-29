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
/// extend it once more, same reasoning (`docs/decisions.md` ADR-015). The
/// Phase 4 KDS values (`acknowledgeKitchenItem` onward) extend it a final
/// time — kitchen ticket reprints deliberately reuse the existing
/// `reprintOrDuplicateReceipt` value rather than adding a duplicate
/// (`docs/decisions.md` ADR-016). The Phase 5 courier-operations values
/// (`activateCourier` onward) extend it once more, from the new
/// `lib/features/courier` feature — confirmed reusable directly by this
/// enum/policy's own long-standing "generic action+actor+context, not
/// payment-specific" design (`docs/decisions.md` ADR-017). The Sprint 5A
/// courier-compensation values (`manageCourierCompensationProfile`
/// onward) extend it a final time, same reasoning
/// (`docs/decisions.md` ADR-018).
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
  acknowledgeKitchenItem,
  startKitchenPreparation,
  markKitchenItemReady,
  cancelKitchenLine,
  recallKitchenLine,
  changeKitchenStation,
  completeOrderPreparation,
  activateCourier,
  deactivateCourier,
  reviewCourierShift,
  startCourierShift,
  endCourierShift,
  changeCourierAvailability,
  createDelivery,
  offerDeliveryAssignment,
  respondToDeliveryAssignment,
  manuallyAssignDelivery,
  reassignDelivery,
  cancelDeliveryAssignment,
  confirmRestaurantArrival,
  confirmPackagePickup,
  startDelivery,
  confirmCustomerArrival,
  completeDelivery,
  recordFailedDelivery,
  overrideGeofence,
  accessCustomerContactAction,
  reviewFailureResponsibility,
  manageCourierCompensationProfile,
  scheduleCourierShift,
  calculateCourierEarnings,
  createCourierEarningsAdjustment,
  markCourierEarningsPaid,
  approveCancelledDeliveryEarnings,
}
