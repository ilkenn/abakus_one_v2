import type { CallableRequest } from "firebase-functions/v2/https";
import { requireStaffPermission } from "./staffAuthorization";

/**
 * Reservation-domain entry point onto the generic, permission-based
 * `staffAuthorization.ts` resolver — Faz R.1B.1 REQUIRED fix #1. The
 * original Faz R.1B draft of this file hardcoded
 * `['manager','admin','tenantOwner']` directly here, i.e. `respondTo
 * Reservation` was checking a **role list**, not a **permission**. This
 * function is now a one-line delegation to `requireStaffPermission(...,
 * "manageReservations")` — `respondToReservation.ts` never references a
 * role name at all; every role name lives in exactly one place
 * (`staffAuthorization.ts`'s `DEFAULT_STAFF_ROLE_PERMISSIONS`), matching
 * `RolePermissionMap`'s own "one static mapping, many call sites ask for a
 * permission" shape.
 */
export function requireReservationManagerPermission(
  request: CallableRequest,
  organizationId: string,
): void {
  requireStaffPermission(request, organizationId, "manageReservations");
}
