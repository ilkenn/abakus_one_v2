import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import {
  validateAndNormalizeWeeklySchedule,
  validateAndNormalizeDateOverrides,
  HttpsErrorForValidation,
} from "./branchOperatingHours";

/**
 * Faz R.3A D2 — the write side of `branchOperatingHours/{branchId}`,
 * anticipated but deliberately left unbuilt by Faz R.2's own doc comment
 * ("R.3's admin UI will add one against this exact schema, unchanged").
 * Gated by `manageBranch`, never `manageReservations` — branch-hours
 * configuration and reservation-operations approval are distinct
 * concerns in both the Dart (`PosAuthorizedAction.manageBranch` vs.
 * `.manageReservations`) and now TS permission models; a manager who can
 * confirm/reject reservations is not automatically trusted to change when
 * the branch is open at all.
 *
 * **Never touches an existing Reservation.** Per Faz R.2's own documented
 * invariant (unchanged, re-affirmed here): this callable only writes
 * `branchOperatingHours/{branchId}`. It never reads, and can never
 * "auto-cancel" or otherwise mutate, any `reservations` document — a
 * schedule edit conflicting with an already-confirmed reservation is an
 * operational matter for staff to resolve via the existing propose/reject
 * tools, not something this callable resolves for them.
 *
 * **Cross-tenant fails closed** the same way `assignReservationTable.ts`
 * does: [organizationId] is the caller-supplied claim used only for the
 * permission check itself; the actual write target
 * (`branchOperatingHours/{branchId}`) is verified to already belong to
 * that exact organization (via `branches/{branchId}`) before anything is
 * written — a caller authorized for one organization can never overwrite
 * another organization's branch hours by supplying its `branchId` with
 * their own `organizationId`, or vice versa.
 */
export const updateBranchOperatingHours = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const branchId = requireString(data.branchId, "branchId");

    requireStaffPermission(request, organizationId, "manageBranch");

    let weeklySchedule;
    let dateOverrides;
    try {
      weeklySchedule = validateAndNormalizeWeeklySchedule(data.weeklySchedule);
      dateOverrides = validateAndNormalizeDateOverrides(data.dateOverrides);
    } catch (error) {
      if (error instanceof HttpsErrorForValidation) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }

    const db = getFirestore();
    const branchDoc = await db.collection("branches").doc(branchId).get();
    if (!branchDoc.exists) {
      throw new HttpsError("not-found", "Branch not found.");
    }
    const branch = branchDoc.data()!;
    if (branch.organizationId !== organizationId) {
      // Cross-tenant fails closed as not-found, not a distinguishable
      // "invalid" — mirrors `assignReservationTable.ts`'s own
      // not-found-not-an-existence-oracle precedent.
      throw new HttpsError("not-found", "Branch not found.");
    }

    const restaurantId = String(branch.restaurantId ?? "");

    await db
      .collection("branchOperatingHours")
      .doc(branchId)
      .set(
        {
          branchId,
          organizationId,
          restaurantId,
          weeklySchedule,
          dateOverrides,
          updatedAt: new Date(),
        },
        { merge: false },
      );

    return { branchId, updated: true };
  },
);

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}
