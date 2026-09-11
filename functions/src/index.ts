import { initializeApp } from "firebase-admin/app";

initializeApp();

export { onOrderCreated } from "./onOrderCreated";
export { onOrderCompleted } from "./onOrderCompleted";
export { processAccountDeletion } from "./processAccountDeletion";
export { resolveTableQrToken } from "./resolveTableQrToken";
export { openTableGuestSession } from "./openTableGuestSession";
export { provisionOrganization } from "./provisionOrganization";
export { provisionRestaurant } from "./provisionRestaurant";
export { provisionBranch } from "./provisionBranch";
export { resolveTakeawayQrToken } from "./resolveTakeawayQrToken";
export { openTakeawayGuestSession } from "./openTakeawayGuestSession";
export { submitTakeawayOrder } from "./submitTakeawayOrder";
export { submitReservation } from "./submitReservation";
export { respondToReservation } from "./respondToReservation";
export { respondToProposedChange } from "./respondToProposedChange";
export { reservationSweep, reservationPreorderKdsRelease } from "./reservationSweep";
export { assignReservationTable } from "./assignReservationTable";
export { openReservationTable } from "./openReservationTable";
export { closeReservationTable } from "./closeReservationTable";
export { getReservationBranchInfo } from "./getReservationBranchInfo";
export { getReservationAvailability } from "./getReservationAvailability";
export {
  syncOwnStaffClaims,
  bootstrapFirstAdminAccount,
  registerStaffMember,
  assignStaffRole,
  revokeStaffRole,
  grantStaffBranchAccess,
  revokeStaffBranchAccess,
  setStaffMemberStatus,
} from "./staffMembership";
export { setStaffPermissionOverride } from "./staffPermissionOverrides";
export { listStaffMembersForOrganization } from "./staffDirectory";
export { resolveActorContext } from "./tenantContext";
export { syncOwnPlatformClaims, grantPlatformRole, revokePlatformRole } from "./platformMembership";
export {
  requestDeviceRegistration,
  requestDeviceChallenge,
  issueDeviceSession,
  revokeTrustedDevice,
  suspendTrustedDevice,
  retireTrustedDevice,
} from "./trustedDevice";
export { respondToApprovalRequest, sweepExpiredApprovalRequests } from "./remoteApproval";
export {
  grantEntitlement,
  renewEntitlement,
  suspendEntitlement,
  revokeEntitlement,
  sweepExpiredEntitlementGracePeriods,
} from "./entitlementAdmin";
export { updateBranchOperatingHours } from "./updateBranchOperatingHours";
export { getBranchOperatingHours } from "./getBranchOperatingHours";
export { listReservationsForBranch } from "./listReservationsForBranch";
export { listReservationTablesForArea } from "./listReservationTablesForArea";
export { getReservationBranchInfoForStaff } from "./getReservationBranchInfoForStaff";
export { cancelReservation } from "./cancelReservation";
export { completeReservation } from "./completeReservation";
export { markReservationNoShow } from "./markReservationNoShow";
export { advanceReservationPreorderOrderStatus } from "./advanceReservationPreorderOrderStatus";
export { cancelReservationPreorderOrderForStaff } from "./cancelReservationPreorderOrderForStaff";
export { refundReservationPreorderOrder } from "./refundReservationPreorderOrder";
export {
  onReservationEventCreated,
  reservationNotificationRetrySweep,
} from "./reservationNotificationDelivery";
export { registerDeviceToken } from "./registerDeviceToken";
export {
  searchAddressAutocomplete,
  resolveAddressPlace,
  saveDeliveryAddress,
  reverseGeocodeAddressPoint,
} from "./deliveryPlaces";
export { getPreciseFraudEvidence } from "./getPreciseFraudEvidence";
export { checkDeliveryEligibility } from "./checkDeliveryEligibility";
export { submitDeliveryOrder } from "./submitDeliveryOrder";
export { requestCustomerPhotoUploadGrant } from "./customerPhotoUploadGrants";
export { finalizeCustomerPhotoUpload } from "./finalizeCustomerPhotoUpload";
export { moderateCustomerPhoto } from "./moderateCustomerPhoto";
export { selectCustomerProfilePhoto } from "./selectCustomerProfilePhoto";
export { completeCustomerProfile } from "./completeCustomerProfile";
export { getCustomerProfileCompletionState } from "./getCustomerProfileCompletionState";
export { getCustomerLoyaltySnapshot } from "./getCustomerLoyaltySnapshot";
export { getCustomerLoyaltyHistory } from "./getCustomerLoyaltyHistory";
export { getCustomerLoyaltyRewardCatalog } from "./getCustomerLoyaltyRewardCatalog";
export { onOrderEventCreatedForLoyaltyEarning } from "./loyaltyOrderEarning";
export { onOrderTerminalFailureOrRefund } from "./onOrderTerminalFailureOrRefund";
export { onOrderEventCreatedForLoyaltyRedemptionRestore } from "./loyaltyRedemptionRestore";
export { onOrderEventCreatedForOrderEarnReversal } from "./orderEarnReversal";
export { respondToTakeawayOrder } from "./respondToTakeawayOrder";
export { advanceTakeawayOrderStatus } from "./advanceTakeawayOrderStatus";
export { cancelTakeawayOrder } from "./cancelTakeawayOrder";
export { cancelTakeawayOrderForStaff } from "./cancelTakeawayOrderForStaff";
export { refundTakeawayOrder } from "./refundTakeawayOrder";
export { respondToDeliveryOrder } from "./respondToDeliveryOrder";
export { advanceDeliveryOrderStatus } from "./advanceDeliveryOrderStatus";
export { cancelDeliveryOrder } from "./cancelDeliveryOrder";
export { cancelDeliveryOrderForStaff } from "./cancelDeliveryOrderForStaff";
export { refundDeliveryOrder } from "./refundDeliveryOrder";
export { submitDineInOrder } from "./submitDineInOrder";
export { respondToDineInOrderLines } from "./respondToDineInOrderLines";
export { advanceDineInOrderStatus } from "./advanceDineInOrderStatus";
export { refundDineInOrder } from "./refundDineInOrder";

// AP-3 Wave 1 SECURITY CORRECTION — the sole staff/POS read path for
// tableSessions/guestSubAccounts/checks/checkAllocations (all four are
// `allow read: if false` in firestore.rules for every staff actor).
export { getPosTableOperationalView, getPosBranchTableOverview } from "./posOperationalView";

// AP-3 Wave 2 — money-safe Check/allocation model.
export {
  openCheck,
  cancelCheck,
  finalizeCheckReadyForPayment,
  reopenCheck,
  splitCheckByProduct,
  splitCheckByQuantity,
  splitCheckByCustomer,
  splitCheckEqualByHeadcount,
  splitCheckFreeAmount,
  mergeChecks,
  transferCheckAllocation,
} from "./checkOperations";

// AP-3 Wave 2C/2D — asynchronous, remote-approval-gated typed actions.
export {
  requestCheckFinancialAdjustment,
  reverseCheckFinancialAdjustment,
  requestAcceptedLineCancellation,
  requestBoncukBalanceCorrection,
} from "./checkFinancialAdjustments";

// AP-3 Wave 2 remainder — physical table transfer/merge.
export { transferTableSession, mergeTableSessions } from "./tableSessionTransfer";

// Dine-in Sprint 3 — service requests (waiter call / bill request).
export { createServiceRequest, resolveServiceRequest } from "./serviceRequests";

// AP-3 Wave 2 remainder — QR replacement/counter-proposal backend.
export {
  proposeDineInLineReplacement,
  respondToDineInCounterProposal,
  sweepExpiredDineInCounterProposals,
} from "./dineInCounterProposal";

// AP-3 Wave 3 — Customer Directory (platform + tenant projections, search, restrictions).
export {
  onOrderCreatedForCustomerDirectory,
  listPlatformCustomers,
  searchPlatformCustomersByPhone,
  getPlatformCustomerDetail,
  revealCustomerFullAddressBook,
  setPlatformCustomerRestriction,
  listTenantCustomers,
  searchCustomersForPos,
  getTenantCustomerDetail,
  setTenantCustomerRestriction,
} from "./customerDirectory";

// AP-3 continuation — Customer Directory backfill tooling (gap-filling only, never production-executed this phase).
export {
  runPlatformCustomerDirectoryBackfill,
  runTenantCustomerDirectoryBackfill,
} from "./customerDirectoryBackfill";

// Server-Authoritative Campaign Engine P8-B (2026-08-25) — foundation only,
// not wired into any order-submission path yet. See campaignEngine.ts.
export { getCustomerActiveCampaigns } from "./getCustomerActiveCampaigns";
// Server-Authoritative Campaign Engine P8-C (2026-08-25) — takeaway campaign
// redemption: reservation is wired into submitTakeawayOrder.ts itself
// (below); this is the terminal-release consumer, the campaign sibling of
// onOrderEventCreatedForLoyaltyRedemptionRestore above.
export { onOrderEventCreatedForCampaignUsageRelease } from "./campaignUsageRestore";

// AP-4 Wave A — the canonical payment/tender engine, built directly on
// AP-3's real checks/checkAllocations (paymentEngine.ts's own doc comment).
export { createPaymentIntent, recordPaymentAttempt } from "./paymentEngine";
// AP-4 Wave A — refund architecture (ADR-033): request (staff) + the
// allowlisted remote-approval handler (registered in remoteApproval.ts's
// own closed ACTION_HANDLERS map, never exported as a callable itself).
export { requestPaymentRefund } from "./paymentRefund";

// AP-4 Wave B — the real cash register engine (ADR-045). apply*/*Rejected
// handlers are registered in remoteApproval.ts's own closed ACTION_HANDLERS/
// REJECTION_HANDLERS maps, never exported as callables themselves.
export {
  createCashDrawer,
  requestCashSessionOpen,
  requestCashMovement,
  requestCashAdjustment,
  submitCashCount,
  closeCashSession,
  getDailyRevenueSummary,
} from "./cashRegisterEngine";

// AP-4 Wave C — the fiscal operation journal + offline authorization lease
// engine (ADR-046). No real PAX A910SF/GMP-3 vendor integration exists —
// see fiscalAdapter.ts's own doc comment and docs/ap4_wave_c_vendor_dependencies.md.
export { recordFiscalOperation, issueOfflineLease, revokeOfflineLease } from "./fiscalEngine";

// AP-4 Wave D — the real payment-session read boundary the checkout UI
// polls after every action; mirrors getPosTableOperationalView's own
// trusted-device-gated, total-Firestore-lockdown reasoning.
export { getPaymentSessionOperationalView } from "./paymentOperationalView";

// AP-4 Wave D — the real cash session read boundary the cash register UI
// polls after every action.
export { listCashDrawers, getCashSessionOperationalView } from "./cashOperationalView";

// AP-4 Wave D — the real branch-wide read boundary Admin's financial
// destinations consume (cash sessions/payments/refunds/fiscal journal/
// offline leases).
export {
  listPaymentSessionsForBranch,
  listRefundsForBranch,
  listCashSessionsForBranch,
  listFiscalOperationsForBranch,
  listOfflineLeasesForBranch,
} from "./adminFinancialView";

// AP-5 Sprint 1 — the real, server-authoritative KitchenWorkItem state
// transition, closing the AP-0/AP-1-confirmed "KDS state is entirely
// in-memory" gap.
export { transitionKitchenWorkItem } from "./transitionKitchenWorkItem";

// AP-5 Sprint 2 — the real writers for product<->recipe/packaging
// linking, closing "no menu product currently references a recipe id at
// all" (`ConsumeStockForOrder`'s own disclosure).
export { setRecipeIngredientLink } from "./setRecipeIngredientLink";
export { setProductPackagingLink } from "./setProductPackagingLink";

// AP-5 Sprint 5 — the real writer for `standardIngredientCosts`, closing
// the "costing feature is 100% client-side, no server-readable unit cost
// exists" gap `acceptOrderLine.ts`'s cost-snapshot step needs.
export { setStandardIngredientCost } from "./setStandardIngredientCost";

// AP-5 Sprint 3 — physical stock count submission; approval/rejection is
// handled through the existing `respondToApprovalRequest` (registered in
// remoteApproval.ts), not a separate callable.
export { submitStockCount } from "./submitStockCount";

// AP-5 Sprint 4 — the real writers for the `printJobs` queue. The
// automatic per-order job (opened at acceptance) is created inline inside
// `acceptOrderLine.ts`'s four call sites, not through either of these
// callables — `requestPrintJob` is the manual KDS-card "Fiş Yazdır /
// Tekrar Yazdır" trigger, `recordPrintOutcome` the manual-override/future
// -real-printer-worker seam.
export { requestPrintJob } from "./requestPrintJob";
export { recordPrintOutcome } from "./recordPrintOutcome";

// AP-6 Sprint 1 — Takeaway Operational States, Busy Mode & Scheduled
// Orders. `updateTakeawayOperationStatus` is the sole writer of
// `branchTakeawaySettings/{branchId}`; `takeawayOperationsSweep` is the
// second `onSchedule` function in this codebase (see its own doc comment
// for why it mirrors `reservationSweep`'s bundled-concerns shape).
export { updateTakeawayOperationStatus } from "./updateTakeawayOperationStatus";
export { takeawayOperationsSweep } from "./takeawayOperationsSweep";

// AP-6 Sprint 2 — Courier Dispatch, FIFO Rotation & Tracking Isolation.
// `setCourier` is the minimal roster-seeding upsert; `assignCourierToOrder`
// is the manual FIFO-informed dispatch callable; `markCourierReturned`
// confirms a courier's physical return to the branch (see its own doc
// comment for why this is deliberately separate from delivery completion,
// which `advanceDeliveryOrderStatus.ts` already handles as a side effect).
export { setCourier } from "./setCourier";
export { assignCourierToOrder } from "./assignCourierToOrder";
export { markCourierReturned } from "./markCourierReturned";

// AP-6 Sprint 3 — Neighborhood Clustering, Multi-Merchant Dispatch &
// Settlement. `registerConsortiumOrder` creates an external-merchant
// delivery order directly at `readyForPickup`, never touching our own
// kitchen; `batchAssignCourierToOrders` is the multi-pickup/multi-drop
// sibling of `assignCourierToOrder` for assigning several orders to one
// courier at once. `ConsortiumDeliverySettlement` creation is a side
// effect of `advanceDeliveryOrderStatus.ts`'s existing completion hook,
// not a separate callable.
export { registerConsortiumOrder } from "./registerConsortiumOrder";
export { batchAssignCourierToOrders } from "./batchAssignCourierToOrders";
