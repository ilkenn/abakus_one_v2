import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { BRANCH_TAKEAWAY_BUSY_DELAY_OPTIONS, type TakeawayOperationStatus } from "./branchTakeawaySettings";

/**
 * AP-6 Sprint 1 — the sole writer of `branchTakeawaySettings/{branchId}`.
 * Reuses `manageTakeawayOrders` (already exists, already staff-tier — see
 * `staffAuthorization.ts`) rather than a new permission, mirroring
 * `respondToTakeawayOrder.ts`/`cancelTakeawayOrderForStaff.ts`'s own gate:
 * changing how the branch is currently operating is the same class of
 * decision as accepting/rejecting an individual order.
 *
 * The four fixed pause durations (30 min / 1 hour / 2 hours / end-of-day)
 * and the custom-date option are all resolved to an absolute [pausedUntil]
 * instant CLIENT-SIDE before this callable is called — matches
 * `updateBranchOperatingHours.ts`/`setStandardIngredientCost.ts`'s own
 * "fully-resolved values in, no duration math server-side" precedent. This
 * callable only validates that the resolved instant is actually in the
 * future.
 *
 * **Cross-tenant fails closed** the same way `updateBranchOperatingHours.ts`
 * does: [organizationId] is the caller-supplied claim used only for the
 * permission check; the write target (`branches/{branchId}`) is verified to
 * already belong to that exact organization before anything is written.
 */
export const updateTakeawayOperationStatus = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const branchId = requireString(data.branchId, "branchId");
    const status = requireStatus(data.status);

    requireStaffPermission(request, organizationId, "manageTakeawayOrders");

    let busyDelayMinutes = 0;
    let pausedUntil: Date | null = null;

    if (status === "busy") {
      if (
        typeof data.busyDelayMinutes !== "number" ||
        !BRANCH_TAKEAWAY_BUSY_DELAY_OPTIONS.includes(data.busyDelayMinutes)
      ) {
        throw new HttpsError(
          "invalid-argument",
          `busyDelayMinutes must be one of: ${BRANCH_TAKEAWAY_BUSY_DELAY_OPTIONS.join(", ")}.`,
        );
      }
      busyDelayMinutes = data.busyDelayMinutes;
    }

    if (status === "paused") {
      if (typeof data.pausedUntil !== "string") {
        throw new HttpsError("invalid-argument", "pausedUntil is required when status is \"paused\".");
      }
      const parsed = new Date(data.pausedUntil);
      if (Number.isNaN(parsed.getTime())) {
        throw new HttpsError("invalid-argument", "pausedUntil is not a valid date.");
      }
      if (parsed.getTime() <= Date.now()) {
        throw new HttpsError("invalid-argument", "pausedUntil must be in the future.");
      }
      pausedUntil = parsed;
    }

    const db = getFirestore();
    const branchDoc = await db.collection("branches").doc(branchId).get();
    if (!branchDoc.exists) {
      throw new HttpsError("not-found", "Branch not found.");
    }
    const branch = branchDoc.data()!;
    if (branch.organizationId !== organizationId) {
      // Cross-tenant fails closed as not-found — mirrors
      // `updateBranchOperatingHours.ts`'s own precedent.
      throw new HttpsError("not-found", "Branch not found.");
    }
    const restaurantId = String(branch.restaurantId ?? "");

    const settingsRef = db.collection("branchTakeawaySettings").doc(branchId);

    return db.runTransaction(async (tx) => {
      const existing = await tx.get(settingsRef);
      const revision = existing.exists ? (Number(existing.data()!.revision ?? 1) + 1) : 1;

      tx.set(
        settingsRef,
        {
          branchId,
          organizationId,
          restaurantId,
          status,
          busyDelayMinutes,
          pausedUntil: pausedUntil ? Timestamp.fromDate(pausedUntil) : null,
          updatedByStaffId: request.auth!.uid,
          updatedAt: Timestamp.now(),
          revision,
        },
        { merge: false },
      );

      return { branchId, status, revision };
    });
  },
);

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

function requireStatus(value: unknown): TakeawayOperationStatus {
  if (value === "active" || value === "busy" || value === "paused") {
    return value;
  }
  throw new HttpsError("invalid-argument", 'status must be one of "active", "busy", "paused".');
}
