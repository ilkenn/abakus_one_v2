import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";

/**
 * AP-2 Stage B — the read-model half of "Staff Admin UI wired to real
 * backend". `firestore.rules`' `memberships` rule deliberately restricts a
 * client to reading only their OWN membership document
 * (`membershipId == resource.data.organizationId + '_' + request.auth.uid`)
 * — an admin cannot list every OTHER staff member's membership via a direct
 * Firestore query at all, by design. This callable is the one real,
 * server-authorized read path for "show me every staff member in my
 * organization," gated by the same `manageStaffAccounts`/`manageStaffRoles`
 * permission the mutating staff callables already use — a caller without
 * either sees nothing.
 *
 * Returns a minimal, display-safe projection — never the raw membership
 * document (no `permissionOverrides` map, no `version` internals) — the
 * Flutter `StaffManagementScreen`/`StaffDetailScreen` UI-layer wiring that
 * consumes this is separate, remaining scope (see `docs/decisions.md`'s
 * AP-2 entry): this file closes the backend gap only.
 */

export interface StaffDirectoryEntry {
  uid: string;
  roles: string[];
  branchAccess: string[];
  status: string;
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) invalid(`${field} is required.`);
  return value as string;
}

export const listStaffMembersForOrganization = onCall(async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");

  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const hasReadPermission = (() => {
    try {
      requireStaffPermission(request, organizationId, "manageStaffAccounts");
      return true;
    } catch {
      try {
        requireStaffPermission(request, organizationId, "manageStaffRoles");
        return true;
      } catch {
        return false;
      }
    }
  })();
  if (!hasReadPermission) {
    throw new HttpsError(
      "permission-denied",
      "manageStaffAccounts or manageStaffRoles authorization is required to list staff.",
    );
  }

  const db = getFirestore();
  const snapshot = await db.collection("memberships").where("organizationId", "==", organizationId).get();
  const members: StaffDirectoryEntry[] = snapshot.docs.map((doc) => {
    const record = doc.data() as { uid: string; roles: string[]; branchAccess: string[]; status: string };
    return { uid: record.uid, roles: record.roles, branchAccess: record.branchAccess, status: record.status };
  });

  return { members };
});
