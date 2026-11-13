import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { requireStaffPermission } from "./staffAuthorization";
import type { MembershipRole } from "./staffMembership";

/**
 * ADR-085 — who may manage which staff account. One rule for every staff
 * command: the panel callables (`staffAccounts.ts`) and the older per-field
 * callables (`assignStaffRole`, `revokeStaffRole`, `grantStaffBranchAccess`,
 * `revokeStaffBranchAccess`, `setStaffMemberStatus` in `staffMembership.ts`).
 *
 * - An admin/owner (`manageStaffAccounts`) manages every account of the
 *   organization except accounts holding `admin` or `tenantOwner` (no peer
 *   or superior). Granting `admin` additionally needs
 *   `manageStaffAdminRole`; `tenantOwner` is never granted by a staff
 *   command.
 * - A manager (`manageStaffRoles` + `manageStaffBranchAccess`) manages only
 *   accounts whose roles are all below the manager tier and whose branches
 *   are all their own (at least one) — checked on the account as it is and
 *   as it would become.
 * - Changing whether an account is active (suspend, reactivate, archive)
 *   is admin/owner only ([assertOrganizationScope]).
 */

/** Roles a manager may manage: those below the manager tier. */
export const BRANCH_MANAGEABLE_ROLES: ReadonlySet<MembershipRole> = new Set([
  "staff",
  "cashier",
  "packingLead",
  "courier",
]);

/** Roles whose holders are off-limits to every scope (no peer/superior). */
const PROTECTED_ROLES: ReadonlySet<MembershipRole> = new Set(["admin", "tenantOwner"]);

export type StaffScope =
  | { kind: "organization"; canGrantAdmin: boolean }
  | { kind: "branch"; branches: ReadonlySet<string> };

export interface AccessShape {
  roles: MembershipRole[];
  branchAccess: string[];
}

function denied(message: string): never {
  throw new HttpsError("permission-denied", message);
}

export async function holdsPermission(
  request: CallableRequest,
  organizationId: string,
  permission: Parameters<typeof requireStaffPermission>[2],
): Promise<boolean> {
  try {
    await requireStaffPermission(request, organizationId, permission);
    return true;
  } catch (error) {
    if (error instanceof HttpsError && error.code === "permission-denied") return false;
    throw error;
  }
}

/** See the module comment. Throws `permission-denied` for anyone else. */
export async function resolveStaffScope(request: CallableRequest, organizationId: string): Promise<StaffScope> {
  if (await holdsPermission(request, organizationId, "manageStaffAccounts")) {
    return {
      kind: "organization",
      canGrantAdmin: await holdsPermission(request, organizationId, "manageStaffAdminRole"),
    };
  }
  await requireStaffPermission(request, organizationId, "manageStaffRoles");
  await requireStaffPermission(request, organizationId, "manageStaffBranchAccess");
  const byOrg = request.auth?.token?.branchAccess as Record<string, unknown> | undefined;
  const own = byOrg?.[organizationId];
  const branches = new Set(Array.isArray(own) ? own.filter((b): b is string => typeof b === "string") : []);
  return { kind: "branch", branches };
}

/** Whether [scope] may hold an account shaped like [access] (checked before AND after a change). */
export function assertWithinScope(scope: StaffScope, access: AccessShape): void {
  if (scope.kind === "organization") {
    if (access.roles.includes("tenantOwner")) denied("The owner role cannot be managed from the panel.");
    if (access.roles.includes("admin") && !scope.canGrantAdmin) denied("Granting the admin role requires manageStaffAdminRole.");
    return;
  }
  const ok =
    access.branchAccess.length > 0 &&
    access.roles.every((role) => BRANCH_MANAGEABLE_ROLES.has(role)) &&
    access.branchAccess.every((branchId) => scope.branches.has(branchId));
  if (!ok) {
    denied("A manager can manage only cashier/courier-level staff, and only in their own branches.");
  }
}

/** An existing account is off-limits if it holds a protected role (no peer/superior), for every scope. */
export function assertTargetNotProtected(access: AccessShape): void {
  if (access.roles.some((role) => PROTECTED_ROLES.has(role))) {
    denied("Admin and owner accounts cannot be managed by another staff member.");
  }
}

/** Activation changes (suspend, reactivate, archive) are admin/owner only. */
export function assertOrganizationScope(scope: StaffScope): void {
  if (scope.kind !== "organization") {
    denied("Only an admin or owner can change whether a staff member is active.");
  }
}
