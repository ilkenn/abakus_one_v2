import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { loadBranchOperatingHours } from "./branchOperatingHours";

/**
 * Faz R.3A — the read-side counterpart to `updateBranchOperatingHours`.
 * `branchOperatingHours` has no client Firestore read path at all (Faz
 * R.2: "this collection has no match block and falls through to the
 * existing fail-closed catch-all") — customer-facing screens never needed
 * one (`submitReservation`/`getReservationAvailability` read it
 * server-side only), but the admin hours editor needs to display the
 * *current* schedule before letting staff change it.
 *
 * **Faz R.3A.1 correction**: originally gated on `manageReservations`
 * (deliberately broader than the write side, on the reasoning that anyone
 * managing reservations benefits from seeing branch hours for calendar/
 * availability context). That created a real inconsistency: branch
 * operating hours are a dedicated `manageBranch`-scoped settings surface —
 * the same permission `updateBranchOperatingHours` already required — and
 * a `manageReservations`-only staff member reading them via this callable
 * had no legitimate need to, since the admin reservation-operations screen
 * itself never calls this callable (it gets its own area/availability
 * context through the separate `manageReservations`-gated
 * `getReservationBranchInfoForStaff`). Both read and write now require
 * `manageBranch`, matching `updateBranchOperatingHours` exactly — no
 * reservation-specific read path is implicitly tied to `manageBranch`, and
 * no branch-settings read path is implicitly tied to `manageReservations`.
 */
export const getBranchOperatingHours = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const branchId = requireString(data.branchId, "branchId");

    requireStaffPermission(request, organizationId, "manageBranch");

    const db = getFirestore();
    const branchDoc = await db.collection("branches").doc(branchId).get();
    if (!branchDoc.exists || branchDoc.data()!.organizationId !== organizationId) {
      throw new HttpsError("not-found", "Branch not found.");
    }

    const hours = await loadBranchOperatingHours(db, branchId);
    if (!hours) {
      return { exists: false, weeklySchedule: null, dateOverrides: null };
    }

    const toHHmm = (minute: number) =>
      `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
    const intervalsOut = (intervals: { startMinute: number; endMinute: number }[]) =>
      intervals.map((i) => ({ start: toHHmm(i.startMinute), end: toHHmm(i.endMinute) }));

    return {
      exists: true,
      weeklySchedule: {
        monday: intervalsOut(hours.weeklySchedule.monday),
        tuesday: intervalsOut(hours.weeklySchedule.tuesday),
        wednesday: intervalsOut(hours.weeklySchedule.wednesday),
        thursday: intervalsOut(hours.weeklySchedule.thursday),
        friday: intervalsOut(hours.weeklySchedule.friday),
        saturday: intervalsOut(hours.weeklySchedule.saturday),
        sunday: intervalsOut(hours.weeklySchedule.sunday),
      },
      dateOverrides: Object.fromEntries(
        Object.entries(hours.dateOverrides).map(([dateKey, override]) => [
          dateKey,
          { closed: override.closed, intervals: intervalsOut(override.intervals) },
        ]),
      ),
    };
  },
);

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}
