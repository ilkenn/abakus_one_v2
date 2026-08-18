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
export { updateBranchOperatingHours } from "./updateBranchOperatingHours";
export { getBranchOperatingHours } from "./getBranchOperatingHours";
export { listReservationsForBranch } from "./listReservationsForBranch";
export { listReservationTablesForArea } from "./listReservationTablesForArea";
export { getReservationBranchInfoForStaff } from "./getReservationBranchInfoForStaff";
export { cancelReservation } from "./cancelReservation";
export { completeReservation } from "./completeReservation";
export { markReservationNoShow } from "./markReservationNoShow";
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
