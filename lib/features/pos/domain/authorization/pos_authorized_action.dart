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
/// onward) extend it again, same reasoning (`docs/decisions.md` ADR-018).
/// The Sprint 5B location-tracking values (`grantLocationEmergencyOverride`
/// onward, including `publishOwnLocationOnly` added during the same
/// sprint's Part 11 authorization pass) extend it again
/// (`docs/decisions.md` ADR-019). The Sprint 5C Dispatch & Operations
/// Center values (`reorderCourierDeliverySequence` onward) extend it
/// again (`docs/decisions.md` ADR-020). The Sprint 5D CRM/Feedback values
/// (`manageVisitRewardRules` onward, from the new `lib/features/crm` and
/// `lib/features/feedback` features) extend it once more — the same
/// generic, not-payment-specific design confirmed reusable a fifth time
/// (`docs/decisions.md` ADR-021). The Phase 6 Admin Platform values
/// (`manageStaffAccounts` onward) extend it a sixth time, from the new
/// `lib/features/admin` feature (`docs/decisions.md` ADR-023) — still the
/// same generic contract, not split, though ADR-023 flags that this
/// enum is now approaching the ~150-value threshold ADR-022 named as the
/// trigger for a future bounded-context split. The Phase 7 Smart Setup/
/// Inventory/Food-Intelligence values (`manageSmartImport` onward) extend
/// it a seventh time, from the new `lib/features/inventory`,
/// `lib/features/recipes`, `lib/features/purchasing`,
/// `lib/features/costing`, `lib/features/profitability`, and
/// `lib/features/smart_import` features (`docs/decisions.md` ADR-024) —
/// now past 90 values, closer still to the named split trigger.
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
  grantLocationEmergencyOverride,
  viewCourierLiveTracking,
  startCourierLocationTracking,
  stopCourierLocationTracking,
  resetCourierLocationHistory,
  publishOwnLocationOnly,
  reorderCourierDeliverySequence,
  groupSameDestinationDeliveries,
  transferCourierShift,
  setTemporaryPackageBlocking,
  sendCourierMessage,
  sendBroadcastMessage,
  sendEmergencyMessage,
  manageVisitRewardRules,
  manageSurveys,
  manageCustomerNotificationCampaigns,
  manageCustomerFeedback,
  manageStaffAccounts,
  manageStaffRoles,
  manageStaffAdminRole,
  manageStaffBranchAccess,
  revokeStaffSession,
  viewStaffAudit,
  manageOrganization,
  manageRestaurant,
  manageBranch,
  branchEmergencyStop,
  viewCustomerAdmin,
  manageCustomerAccountStatus,
  moderateCustomerPhoto,
  manageDeviceRegistry,
  viewAuditCenter,
  manageLocalizationConfig,
  viewFeatureFlags,
  manageMaintenanceMode,
  manageSmartImport,
  manageRestaurantSetup,
  manageInventory,
  recordStockMovement,
  recordStockCount,
  approveStockCountAdjustment,
  recordWaste,
  manageRecipes,
  manageNutrition,
  manageAllergens,
  managePurchasing,
  manageSuppliers,
  manageSupplierPricing,
  manageCostingConfiguration,
  viewProfitability,
  manageEntitlements,
  viewAdvancedReporting,
}
