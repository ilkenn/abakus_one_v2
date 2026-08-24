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
  | "moderateCustomerPhotos"
  | "manageTakeawayOrders"
  | "manageTakeawayOrderCancellations"
  | "manageTakeawayOrderRefunds"
  | "manageDeliveryOrders"
  | "manageDeliveryOrderCancellations"
  | "manageDeliveryOrderRefunds";

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
 * - `manageTakeawayOrders` (Boncuk Loyalty P4-C-C-B, 2026-08-22): confirm/
 *   reject a pending takeaway order, advance it through
 *   `confirmed -> preparing -> ready -> completed`, and cancel it while
 *   still `confirmed` (before kitchen prep has actually started). Granted
 *   to `staff` — **the first-ever permission this map has EVER granted to
 *   the `staff` tier** (approved explicitly, P4-C-C-A/P4-C-C-B; every prior
 *   permission here was manager-tier-and-above only, since ordinary
 *   day-to-day order confirm/reject/advance is routine, high-volume
 *   operational work that would make the whole takeaway channel unusable
 *   if it required a manager for every single order) — as well as
 *   `manager`/`admin`/`tenantOwner`.
 * - `manageTakeawayOrderCancellations` (Boncuk Loyalty P4-C-C-B): the
 *   ESCALATED tier — cancelling a takeaway order that has already entered
 *   `preparing` or `ready` (real kitchen time/inventory already
 *   committed — a loss-prevention/accountability decision, deliberately
 *   `_managerTier`-and-above only, mirroring every other manager-gated
 *   permission in this map). `staff` is intentionally NOT granted this one
 *   — see `manageTakeawayOrders` above for the boundary this draws.
 * - `manageTakeawayOrderRefunds` (Boncuk Loyalty P4-D-B, 2026-08-22):
 *   `completed -> refunded` — a strictly more consequential action than any
 *   pre-fulfillment cancellation (it reverses an order the business already
 *   recorded as complete, and may trigger BOTH a Boncuk redemption restore
 *   AND an earned-Boncuk clawback at once). Deliberately its OWN dedicated
 *   permission, never reusing `manageTakeawayOrderCancellations` — the two
 *   actions are conceptually distinct (mid-lifecycle cancellation vs.
 *   post-completion refund) and conflating them under one name would be
 *   less honest/auditable. `_managerTier`-and-above only — `staff` is
 *   deliberately NOT granted this one, same boundary as
 *   `manageTakeawayOrderCancellations`.
 * - `manageDeliveryOrders` / `manageDeliveryOrderCancellations` /
 *   `manageDeliveryOrderRefunds` (Boncuk Loyalty P5-B, 2026-08-24): the
 *   DELIVERY-channel analogues of the three `manageTakeawayOrder*`
 *   permissions above, same exact tiering rationale, deliberately three
 *   SEPARATE permissions from their takeaway counterparts (never reused —
 *   a staff member scoped to takeaway operations must not automatically
 *   gain delivery lifecycle authority, and vice versa; the two channels
 *   have genuinely different operational teams in a real restaurant).
 *   `manageDeliveryOrders` covers confirm/reject/`confirmed -> preparing
 *   -> ready -> outForDelivery -> completed`/`confirmed -> cancelled` —
 *   granted to `staff` (day-to-day operational volume, same reasoning as
 *   `manageTakeawayOrders`) and `manager`/`admin`/`tenantOwner`.
 *   `manageDeliveryOrderCancellations` covers cancelling from
 *   `preparing`/`ready`/`outForDelivery` (real kitchen/courier time
 *   already committed) — `_managerTier`-and-above only, `staff`
 *   deliberately excluded, same boundary as
 *   `manageTakeawayOrderCancellations`. `manageDeliveryOrderRefunds`
 *   covers `completed -> refunded` — `_managerTier`-and-above only, its
 *   own dedicated permission for the same reason
 *   `manageTakeawayOrderRefunds` is. `courier` is granted NONE of these
 *   three in this phase — courier-authoritative delivery completion is
 *   explicitly deferred until a canonical courier assignment/lifecycle
 *   integration exists (P5-B's own locked scope).
 *
 * Role name strings match `StaffRole.name` / the custom-claims `roles` map
 * convention already established by `platformAuthorization.ts`/
 * `firestore.rules`'s own `hasRole`.
 */
export const DEFAULT_STAFF_ROLE_PERMISSIONS: Readonly<Record<string, readonly StaffPermission[]>> = {
  // Boncuk Loyalty P4-C-C-B — the first-ever `staff`-tier entry in this
  // map. Deliberately narrow: ONLY `manageTakeawayOrders`, never any
  // existing manager-tier permission — an ordinary staff member must never
  // gain `manageReservations`/`manageBranch`/etc. as an accidental side
  // effect of this addition.
  staff: ["manageTakeawayOrders", "manageDeliveryOrders"],
  manager: [
    "manageReservations",
    "manageBranch",
    "manageStaffBranchAccess",
    "manageStaffRoles",
    "moderateCustomerPhotos",
    "manageTakeawayOrders",
    "manageTakeawayOrderCancellations",
    "manageTakeawayOrderRefunds",
    "manageDeliveryOrders",
    "manageDeliveryOrderCancellations",
    "manageDeliveryOrderRefunds",
  ],
  admin: [
    "manageReservations",
    "manageBranch",
    "manageStaffBranchAccess",
    "manageStaffRoles",
    "manageStaffAdminRole",
    "manageStaffAccounts",
    "moderateCustomerPhotos",
    "manageTakeawayOrders",
    "manageTakeawayOrderCancellations",
    "manageTakeawayOrderRefunds",
    "manageDeliveryOrders",
    "manageDeliveryOrderCancellations",
    "manageDeliveryOrderRefunds",
  ],
  tenantOwner: [
    "manageReservations",
    "manageBranch",
    "manageStaffBranchAccess",
    "manageStaffRoles",
    "manageStaffAdminRole",
    "manageStaffAccounts",
    "moderateCustomerPhotos",
    "manageTakeawayOrders",
    "manageTakeawayOrderCancellations",
    "manageTakeawayOrderRefunds",
    "manageDeliveryOrders",
    "manageDeliveryOrderCancellations",
    "manageDeliveryOrderRefunds",
  ],
  // `courier` deliberately has no entry at all — zero permissions, exactly
  // like every role not listed here. Explicit instruction: courier must
  // never gain takeaway OR delivery lifecycle authority in this phase.
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

/**
 * Server-authoritative branch-scoping check — Boncuk Loyalty P4-C-C-B
 * (2026-08-22), the Cloud-Functions-side mirror of `firestore.rules`'s
 * `hasBranchAccess(organizationId, branchId)` (confirmed by direct
 * inspection before writing this — same claim, same shape, no new
 * semantics invented). `branchAccess` is a custom claim map
 * `{[organizationId]: [branchId, ...]}`, synced from
 * `memberships/{organizationId}_{uid}`'s own `branchAccess` array field by
 * `staffMembership.ts`'s `resyncClaimsForUid` — never a client-supplied
 * value, and never a role-based bypass: this codebase's branch-access
 * model has no wildcard/"all branches" semantics for any role, not even
 * `admin`/`tenantOwner` (`bootstrapFirstAdminAccount` itself starts with
 * `branchAccess: []`).
 *
 * **This is the first Cloud Function to enforce branch-level authorization
 * server-side** — every existing staff callable audited before writing
 * this (`listReservationsForBranch`/`getReservationBranchInfoForStaff`/
 * `respondToReservation`) checks only ORGANIZATION-level permission via
 * `requireStaffPermission`, relying on Firestore query filtering alone for
 * branch scoping. `firestore.rules`' own `orders` READ rule already
 * requires `hasBranchAccess` in addition to `isOrgMember` (a prior,
 * documented tightening — org-only access let any staff member read every
 * branch's orders, "unacceptable for the multi-branch SaaS architecture").
 * Every takeaway lifecycle callable in this file's sibling modules matches
 * that same bar on the write side for the first time, rather than
 * repeating the org-only gap other callables still have.
 *
 * Always call AFTER `requireStaffPermission` for the same `organizationId`
 * — this function does not itself re-verify organization membership
 * (`hasBranchAccess`'s own rules-side definition also composes
 * `isOrgMember` first; callers here get the identical layering by calling
 * both functions in sequence). Fails closed structurally: a missing
 * `branchAccess` claim key, a missing `organizationId` entry, or a
 * malformed (non-array) value all resolve to denied, never to an
 * exception a caller could mistake for something else.
 */
export function requireBranchAccess(
  request: CallableRequest,
  organizationId: string,
  branchId: string,
): void {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const token = request.auth.token;
  const branchAccessByOrg = token?.branchAccess as Record<string, unknown> | undefined;
  const branchesForOrg = branchAccessByOrg?.[organizationId];
  const authorized = Array.isArray(branchesForOrg) && branchesForOrg.includes(branchId);
  if (!authorized) {
    throw new HttpsError(
      "permission-denied",
      "Branch authorization is required for this operation.",
    );
  }
}
