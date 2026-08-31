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
