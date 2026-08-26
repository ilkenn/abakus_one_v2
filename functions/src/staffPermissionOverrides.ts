import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import {
  DEFAULT_STAFF_ROLE_PERMISSIONS,
  requireBranchAccess,
  requireStaffPermission,
} from "./staffAuthorization";
import type { StaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";

/**
 * AP-2 Stage B — per-staff-member permission overrides, the capability
 * `staffAuthorization.ts`'s own doc comment flagged as absent when it was
 * written (Faz R.1B.1: "No Dart-side per-staff permission override exists
 * yet... this module is deliberately built so that becomes possible
 * without changing any callable"). This file is that seam being used, not
 * a redesign of `staffAuthorization.ts` itself — `roleHasPermission`,
 * `DEFAULT_STAFF_ROLE_PERMISSIONS`, `requireStaffPermission`, and
 * `requireBranchAccess` are all reused unmodified; every existing
 * pre-AP-2 callable keeps calling the original, claims-only
 * `requireStaffPermission` exactly as before.
 *
 * **Correction #1 (AP-2 Stage B, mandatory)** — the effective-permission
 * formula is a set union/subtraction, never `XOR`:
 *
 * ```text
 * effectivePermissions =
 *   (union(rolePermissions) + organizationGrants + branchGrants)
 *   - organizationDenies
 *   - branchDenies
 * ```
 *
 * Deny always wins over any grant or role-derived permission, at either
 * scope. Organization and branch overrides are stored and applied
 * separately (a branch-scoped grant never leaks to a different branch of
 * the same organization).
 *
 * **Correction #1 — claims stay a bounded cache.** Overrides are never
 * copied into Firebase Auth custom claims (which already carry
 * `organizationAccess`/`roles`/`branchAccess` — small, bounded lists);
 * copying a whole permission map into the token would make it unbounded
 * and stale-prone. Instead, [requireDurablePermission] re-reads the
 * durable `memberships` document on every call — the read is cheap (one
 * document get) and guarantees a revoked membership or a just-added deny
 * takes effect immediately, never waiting for the caller's ID token to be
 * refreshed. This is the "critical mutation revalidates against the
 * durable backend record" rule (Correction #1/#10) applied concretely.
 */

export type PermissionEffect = "grant" | "deny";

export interface PermissionOverrideMap {
  organization?: Partial<Record<StaffPermission, PermissionEffect>>;
  branch?: Record<string, Partial<Record<StaffPermission, PermissionEffect>>>;
}

interface MembershipRecord {
  organizationId: string;
  uid: string;
  roles: string[];
  branchAccess: string[];
  status: "active" | "suspended" | "archived";
  permissionOverrides?: PermissionOverrideMap;
  version?: number;
}

function membershipId(organizationId: string, uid: string): string {
  return `${organizationId}_${uid}`;
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    invalid(`${field} is required.`);
  }
  return value as string;
}

/**
 * Overriding one of these requires the caller to hold `manageStaffAdminRole`
 * themselves — mirrors `staffMembership.ts`'s `roleGrantPermission` split
 * ("no manager granting admin unless authorized") applied to overrides too.
 * Every other permission requires only `manageStaffRoles`.
 */
const ADMIN_TIER_PERMISSIONS: ReadonlySet<StaffPermission> = new Set<StaffPermission>([
  "manageStaffAdminRole",
  "manageStaffAccounts",
]);

function overrideMetaPermission(permission: StaffPermission): StaffPermission {
  return ADMIN_TIER_PERMISSIONS.has(permission) ? "manageStaffAdminRole" : "manageStaffRoles";
}

/** The set-union/subtraction formula — see this file's own top doc comment. Pure, no I/O, independently testable. */
export function resolveEffectivePermissions(
  roles: readonly string[],
  overrides: PermissionOverrideMap | undefined,
  branchId: string | null,
  rolePermissions: Readonly<Record<string, readonly StaffPermission[]>> = DEFAULT_STAFF_ROLE_PERMISSIONS,
): Set<StaffPermission> {
  const effective = new Set<StaffPermission>();
  for (const role of roles) {
    for (const permission of rolePermissions[role] ?? []) {
      effective.add(permission);
    }
  }

  const orgOverrides = overrides?.organization ?? {};
  const branchOverrides = (branchId && overrides?.branch?.[branchId]) || {};

  for (const [permission, effect] of Object.entries(orgOverrides)) {
    if (effect === "grant") effective.add(permission as StaffPermission);
  }
  for (const [permission, effect] of Object.entries(branchOverrides)) {
    if (effect === "grant") effective.add(permission as StaffPermission);
  }
  // Deny always wins — applied last, unconditionally, at both scopes.
  for (const [permission, effect] of Object.entries(orgOverrides)) {
    if (effect === "deny") effective.delete(permission as StaffPermission);
  }
  for (const [permission, effect] of Object.entries(branchOverrides)) {
    if (effect === "deny") effective.delete(permission as StaffPermission);
  }

  return effective;
}

async function loadMembership(
  db: FirebaseFirestore.Firestore,
  organizationId: string,
  uid: string,
): Promise<{ ref: FirebaseFirestore.DocumentReference; data: MembershipRecord }> {
  const ref = db.collection("memberships").doc(membershipId(organizationId, uid));
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "No membership found for this account in this organization.");
  }
  return { ref, data: snap.data() as MembershipRecord };
}

/**
 * The durable, override-aware, stale-membership-checked permission gate —
 * used by AP-2's own new sensitive commands. Fails closed on a missing or
 * non-active membership, or a missing branch access grant, before ever
 * consulting the effective-permission set.
 */
export async function requireDurablePermission(
  request: CallableRequest,
  organizationId: string,
  permission: StaffPermission,
  branchId: string | null = null,
): Promise<MembershipRecord> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const db = getFirestore();
  const { data } = await loadMembership(db, organizationId, request.auth.uid);
  if (data.status !== "active") {
    throw new HttpsError("permission-denied", "This membership is not active.");
  }
  if (branchId && !data.branchAccess.includes(branchId)) {
    throw new HttpsError("permission-denied", "Branch authorization is required for this operation.");
  }
  const effective = resolveEffectivePermissions(data.roles, data.permissionOverrides, branchId);
  if (!effective.has(permission)) {
    throw new HttpsError(
      "permission-denied",
      `${permission} authorization is required for this organization.`,
    );
  }
  return data;
}

interface ParsedInput {
  organizationId: string;
  targetUid: string;
  permission: StaffPermission;
  scope: "organization" | "branch";
  branchId: string | null;
  effect: PermissionEffect | "clear";
  clientRequestId: string | null;
}

function parseInput(data: Record<string, unknown>): ParsedInput {
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const targetUid = requireNonEmptyString(data.targetUid, "targetUid");
  const permission = requireNonEmptyString(data.permission, "permission") as StaffPermission;
  const scope = requireNonEmptyString(data.scope, "scope");
  if (scope !== "organization" && scope !== "branch") {
    invalid('scope must be "organization" or "branch".');
  }
  const effect = requireNonEmptyString(data.effect, "effect");
  if (effect !== "grant" && effect !== "deny" && effect !== "clear") {
    invalid('effect must be "grant", "deny", or "clear".');
  }
  let branchId: string | null = null;
  if (scope === "branch") {
    branchId = requireNonEmptyString(data.branchId, "branchId");
  }
  return {
    organizationId,
    targetUid,
    permission,
    scope,
    branchId,
    effect: effect as PermissionEffect | "clear",
    clientRequestId: typeof data.clientRequestId === "string" ? data.clientRequestId : null,
  };
}

/**
 * Grants, denies, or clears a single permission override for [targetUid],
 * scoped to either the whole organization or one branch. Self-modification
 * is structurally forbidden (Correction #1: "Self-grant ve self-deny-removal
 * yasaktır") — a staff member can never grant themselves a permission NOR
 * remove/weaken a deny placed on themselves, both blocked by the same
 * `targetUid === caller` check regardless of [effect].
 */
export const setStaffPermissionOverride = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const input = parseInput((request.data ?? {}) as Record<string, unknown>);

    if (input.targetUid === request.auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "A staff member cannot modify their own permission overrides.",
      );
    }

    const metaPermission = overrideMetaPermission(input.permission);
    requireStaffPermission(request, input.organizationId, metaPermission);
    if (input.scope === "branch") {
      requireBranchAccess(request, input.organizationId, input.branchId!);
    }

    const db = getFirestore();

    // Correction #1 — "Caller sahip olmadığı bir permission'ı başkasına
    // veremez": only checked for `grant` (denying/clearing never expands
    // anyone's access, so it carries no such risk).
    if (input.effect === "grant") {
      const { data: callerData } = await loadMembership(db, input.organizationId, request.auth.uid);
      if (callerData.status !== "active") {
        throw new HttpsError("permission-denied", "This membership is not active.");
      }
      const callerEffective = resolveEffectivePermissions(
        callerData.roles,
        callerData.permissionOverrides,
        input.scope === "branch" ? input.branchId : null,
      );
      if (!callerEffective.has(input.permission)) {
        throw new HttpsError(
          "permission-denied",
          "Caller cannot grant a permission they do not themselves hold.",
        );
      }
    }

    const correlationId = generateCorrelationId();
    const clientRequestId = sanitizeClientRequestId(input.clientRequestId);
    const now = Timestamp.now();

    const result = await db.runTransaction(async (tx) => {
      const ref = db.collection("memberships").doc(membershipId(input.organizationId, input.targetUid));
      const snap = await tx.get(ref);
      if (!snap.exists) {
        throw new HttpsError(
          "not-found",
          "No membership found for this account in this organization.",
        );
      }
      const targetData = snap.data() as MembershipRecord;
      if (targetData.status !== "active") {
        throw new HttpsError("permission-denied", "This membership is not active.");
      }

      const organizationOverrides: Partial<Record<StaffPermission, PermissionEffect>> = {
        ...(targetData.permissionOverrides?.organization ?? {}),
      };
      const branchOverridesByBranch: Record<string, Partial<Record<StaffPermission, PermissionEffect>>> = {
        ...(targetData.permissionOverrides?.branch ?? {}),
      };

      const previousEffect: PermissionEffect | null =
        input.scope === "organization"
          ? organizationOverrides[input.permission] ?? null
          : branchOverridesByBranch[input.branchId!]?.[input.permission] ?? null;

      if (input.scope === "organization") {
        if (input.effect === "clear") {
          delete organizationOverrides[input.permission];
        } else {
          organizationOverrides[input.permission] = input.effect;
        }
      } else {
        const branchMap: Partial<Record<StaffPermission, PermissionEffect>> = {
          ...(branchOverridesByBranch[input.branchId!] ?? {}),
        };
        if (input.effect === "clear") {
          delete branchMap[input.permission];
        } else {
          branchMap[input.permission] = input.effect;
        }
        branchOverridesByBranch[input.branchId!] = branchMap;
      }

      const nextVersion = (targetData.version ?? 1) + 1;
      const nextOverrides: PermissionOverrideMap = {
        organization: organizationOverrides,
        branch: branchOverridesByBranch,
      };

      tx.update(ref, {
        permissionOverrides: nextOverrides,
        version: nextVersion,
        updatedAt: now,
      });

      writeAuditEvent({
        tx,
        db,
        eventId:
          `${ref.id}-override-${input.permission}-${input.scope}` +
          `${input.scope === "branch" ? `-${input.branchId}` : ""}-v${nextVersion}`,
        organizationId: input.organizationId,
        branchId: input.scope === "branch" ? input.branchId : null,
        type: "staff.permissionOverrideSet",
        targetRef: ref.path,
        previousValue: previousEffect,
        newValue: input.effect === "clear" ? null : input.effect,
        actorType: "staff",
        actorUid: request.auth!.uid,
        correlationId,
        clientRequestId,
        now,
      });

      return { version: nextVersion };
    });

    return {
      organizationId: input.organizationId,
      targetUid: input.targetUid,
      permission: input.permission,
      scope: input.scope,
      branchId: input.scope === "branch" ? input.branchId : null,
      effect: input.effect,
      version: result.version,
      correlationId,
    };
  },
);
