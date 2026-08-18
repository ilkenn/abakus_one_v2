import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";

/**
 * Generic, permission-based tenant-staff authorization — Faz R.1B.1. This
 * is the TS-side analogue of `RealPosAuthorizationPolicy.authorize`
 * (`lib/features/pos/domain/authorization/real_pos_authorization_policy.dart`)
 * and `RolePermissionMap` (`lib/features/pos/domain/authorization/
 * role_permission_map.dart`) — but, unlike the Faz R.1B first draft of
 * `reservationAuthorization.ts` (which hardcoded `['manager','admin',
 * 'tenantOwner']` directly inside the reservation callable), this module
 * resolves a **permission**, never a role list, at the call site. Role
 * names only ever appear in `DEFAULT_STAFF_ROLE_PERMISSIONS` below — one
 * place, exactly mirroring `RolePermissionMap`'s own "one static mapping,
 * many call sites ask for a permission" shape.
 *
 * **No Dart-side per-staff permission override exists yet** (confirmed by
 * research before writing this file — `StaffMember`/`ActorSession` carry
 * only `roles: Set<StaffRole>`, no independent `permissions` field, and
 * `RealPosAuthorizationPolicy` resolves purely from `RolePermissionMap`).
 * So there is nothing to mirror for "a specific staff member granted a
 * permission outside their role tier" today — this module is deliberately
 * built so that becomes possible **without changing any callable** once
 * that Dart-side mechanism exists: `roleHasPermission`'s `rolePermissions`
 * parameter is the seam a future claims-sync (or a per-organization
 * override document) would populate instead of `DEFAULT_STAFF_ROLE_PERMISSIONS`.
 * Until then, `DEFAULT_STAFF_ROLE_PERMISSIONS` is the real, tested default
 * — not a placeholder — and every reservation callable authorizes through
 * `requireStaffPermission`, never a role-name check of its own.
 */

export type StaffPermission =
  | "manageReservations"
  | "manageBranch"
  | "manageStaffAccounts"
  | "manageStaffAdminRole"
  | "manageStaffRoles"
  | "manageStaffBranchAccess"
  | "moderateCustomerPhotos";

/**
 * The default role -> permission set — Faz R.3A extends this beyond the
 * original `manageReservations`-only mapping, mirroring
 * `RolePermissionMap`'s exact existing tiering for each new permission
 * rather than inventing a new one:
 *
 * - `manageBranch`: `_managerTier` (manager/admin/tenantOwner) — branch-
 *   level configuration (Phase 6 Admin Platform, `docs/decisions.md`
 *   ADR-023), same tier as `manageReservations` itself.
 * - `manageStaffBranchAccess`: `_managerTier` — granting/revoking branch
 *   access.
 * - `manageStaffRoles`: `_managerTier` — granting/revoking any role
 *   *except* `admin` (mirrors `AssignStaffRole`'s own role-scoped split:
 *   `manageStaffRoles` for non-admin roles, `manageStaffAdminRole` for the
 *   admin role specifically — "no manager granting admin unless
 *   authorized").
 * - `manageStaffAdminRole` / `manageStaffAccounts`: `_adminOnly` — granting
 *   the admin role itself, and account registration/status changes
 *   (suspend/reinstate/archive), both admin-only in the Dart model.
 * - `moderateCustomerPhotos`: `_managerTier` — Profile P.4.2B2, mirrors
 *   the Dart `RolePermissionMap`'s own `PosAuthorizedAction
 *   .moderateCustomerPhoto` placement exactly (same tier as
 *   `manageBranch`, `role_permission_map.dart`'s `_managerTier` set).
 *
 * Role name strings match `StaffRole.name` / the custom-claims `roles` map
 * convention already established by `platformAuthorization.ts`/
 * `firestore.rules`'s own `hasRole`.
 */
export const DEFAULT_STAFF_ROLE_PERMISSIONS: Readonly<Record<string, readonly StaffPermission[]>> = {
  manager: [
    "manageReservations",
    "manageBranch",
    "manageStaffBranchAccess",
    "manageStaffRoles",
    "moderateCustomerPhotos",
  ],
  admin: [
    "manageReservations",
    "manageBranch",
    "manageStaffBranchAccess",
    "manageStaffRoles",
    "manageStaffAdminRole",
    "manageStaffAccounts",
    "moderateCustomerPhotos",
  ],
  tenantOwner: [
    "manageReservations",
    "manageBranch",
    "manageStaffBranchAccess",
    "manageStaffRoles",
    "manageStaffAdminRole",
    "manageStaffAccounts",
    "moderateCustomerPhotos",
  ],
};

/**
 * Resolves whether [role] carries [permission] — genuinely data-driven, not
 * a hardcoded role-name `if`/`switch`. [rolePermissions] defaults to the
 * real canonical mapping but is an explicit parameter (not a module-level
 * constant baked into the function body) so the resolution *logic* itself
 * is independently testable against a role/permission combination the
 * default mapping doesn't have an opinion on today — e.g. proving a role
 * outside today's manager-tier would be authorized the moment it's granted
 * the permission, with zero code change to this function or any callable.
 */
export function roleHasPermission(
  role: string,
  permission: StaffPermission,
  rolePermissions: Readonly<Record<string, readonly StaffPermission[]>> = DEFAULT_STAFF_ROLE_PERMISSIONS,
): boolean {
  const permissions = rolePermissions[role];
  return permissions !== undefined && permissions.includes(permission);
}

/**
 * Server-authoritative tenant-staff permission check for a Cloud Function
 * callable — mirrors `platformAuthorization.ts`'s `requirePlatformMember`
 * shape (throw `unauthenticated`/`permission-denied`), but resolves a named
 * [permission] via `roleHasPermission` against every role the caller holds
 * for [organizationId], rather than checking a fixed role list inline.
 * `organizationAccess`/`roles` claim shape mirrors `firestore.rules`'s own
 * `isOrgMember`/`hasRole` exactly — "no role exemption": `organizationId`
 * must appear in `organizationAccess` independently of which roles are
 * held for it.
 */
export function requireStaffPermission(
  request: CallableRequest,
  organizationId: string,
  permission: StaffPermission,
): void {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const token = request.auth.token;
  const organizationAccess = token?.organizationAccess;
  const isOrgMember =
    Array.isArray(organizationAccess) && organizationAccess.includes(organizationId);
  if (!isOrgMember) {
    throw new HttpsError(
      "permission-denied",
      `${permission} authorization is required for this organization.`,
    );
  }
  const rolesByOrg = token?.roles as Record<string, unknown> | undefined;
  const rolesForOrg = rolesByOrg?.[organizationId];
  const authorized =
    Array.isArray(rolesForOrg) &&
    rolesForOrg.some((role) => typeof role === "string" && roleHasPermission(role, permission));
  if (!authorized) {
    throw new HttpsError(
      "permission-denied",
      `${permission} authorization is required for this organization.`,
    );
  }
}
