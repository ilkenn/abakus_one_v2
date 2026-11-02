import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * 2026-10-30 — a narrow, safe rename-only callable for `branches/{branchId}
 * .name`. Deliberately **not** built on `provisionBranch`'s broader
 * upsert: that callable's update path writes `supportedOrderChannelIds`/
 * `timezone`/`currencyCode`/`localeCode`/`status` every time (defaulting
 * any field the caller omits), so reusing it just to fix a display name
 * would silently reset every one of those to their defaults unless the
 * caller first reads back and re-supplies the branch's current values —
 * a real risk this callable avoids entirely by touching `.update()` with
 * only `{ name, updatedAt }`, nothing else.
 *
 * Gated by `manageBranch` (not a platform-level permission) — renaming a
 * branch is an ordinary in-tenant branch-configuration action, the same
 * tier `updateBranchOperatingHours.ts` already uses.
 */
export const renameBranch = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const branchId = requireString(data.branchId, "branchId");
    const name = requireString(data.name, "name");

    await requireStaffPermission(request, organizationId, "manageBranch");

    const db = getFirestore();
    const branchRef = db.collection("branches").doc(branchId);
    const branchDoc = await branchRef.get();
    if (!branchDoc.exists) {
      throw new HttpsError("not-found", "Branch not found.");
    }
    const branch = branchDoc.data()!;
    if (branch.organizationId !== organizationId) {
      // Cross-tenant fails closed as not-found, not a distinguishable
      // "invalid" — mirrors updateBranchOperatingHours.ts's own precedent.
      throw new HttpsError("not-found", "Branch not found.");
    }

    await branchRef.update({ name, updatedAt: new Date() });

    return { branchId, name, updated: true };
  },
);

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}
