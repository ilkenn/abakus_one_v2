import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * Faz R.3A — the scoped Firestore-backed staff/membership foundation.
 * Reuses the exact domain semantics `lib/features/admin/application/
 * use_cases/*.dart` already establishes (role-scoped authorization split
 * between `manageStaffRoles`/`manageStaffAdminRole`, "no self-promotion",
 * revoke-is-a-no-op-if-not-held, status lifecycle, admin-only bootstrap
 * exception) — this file is the first real Cloud Function backing for
 * that domain, not a redesign of it.
 *
 * **Deliberately scoped, not a full Sprint 9E migration.** Persists only
 * `memberships/{organizationId}_{uid}` — the "minimal shape" collection
 * `docs/firestore_data_model.md` already documents as the claims-sync
 * source of truth (`roles`/`branchAccess`/`restaurantAccess`/`status`),
 * not the fuller `staffMembers` admin-display record (display name,
 * audit trail, session-revocation timestamp) that collection's own doc
 * comment distinguishes it from. `restaurantAccess` is carried on the
 * document for schema parity with the Dart `StaffMember`/`ActorSession`
 * model but has no grant/revoke callable in this phase — nothing reads it
 * yet (branch-scoped access is what `manageReservations`/`manageBranch`
 * actually check). `staffMembers`, staff registration audit trail, and
 * the Dart `StaffMember`/`InMemoryStaffMemberRepository` UI layer itself
 * are all explicitly untouched/undone by this phase — remaining Sprint 9E
 * scope, not silently claimed complete.
 *
 * **The bootstrap chain**: `bootstrapFirstAdminAccount` is the one
 * self-authorizing exception (mirrors `BootstrapFirstAdminAccount.dart`'s
 * own "no existing admin to authorize the first one" reasoning), gated
 * only by "no membership exists yet for this organizationId" — never by
 * an existing permission. Every other callable in this file requires a
 * real permission via `requireStaffPermission`, which in turn requires
 * the caller to already hold a real custom-claims token — which only
 * exists after they've called `syncOwnStaffClaims` and refreshed their ID
 * token. `syncOwnStaffClaims` itself is the one callable NOT gated by any
 * existing claim (by design — seeding claims from nothing is its entire
 * purpose); its own safety comes entirely from deriving every claim value
 * server-side off `request.auth.uid`, never trusting any client-supplied
 * organizationId/role/permission.
 */

export type MembershipRole = "staff" | "manager" | "admin" | "tenantOwner" | "courier";
export type MembershipStatus = "active" | "suspended" | "archived";

interface MembershipDoc {
  organizationId: string;
  uid: string;
  roles: MembershipRole[];
  branchAccess: string[];
  restaurantAccess: string[];
  status: MembershipStatus;
  createdAt: FirebaseFirestore.FieldValue | Date;
  updatedAt: FirebaseFirestore.FieldValue | Date;
  /**
   * AP-2 Stage B, Correction #1/#10 — a monotonically increasing counter,
   * bumped on every mutation below. Lets a caller detect a stale read (the
   * durable-permission-check equivalent of `staffPermissionOverrides.ts`'s
   * own re-read-on-every-call discipline) without needing to diff the
   * whole document. Starts at `1` on creation.
   */
  version: number;
}

const VALID_ROLES: readonly MembershipRole[] = ["staff", "manager", "admin", "tenantOwner", "courier"];
const VALID_STATUSES: readonly MembershipStatus[] = ["active", "suspended", "archived"];

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
 * Rebuilds `organizationAccess`/`roles`/`branchAccess` custom claims for
 * [uid] from every one of their *active* membership documents — the exact
 * same derivation `syncOwnStaffClaims` uses for itself, factored out so
 * every mutating callable below (including [grantStaffBranchAccess]/
 * [revokeStaffBranchAccess]) can immediately re-sync the affected user's
 * claims too (never leaving a stale token as the only way to observe a
 * change this callable itself just made).
 *
 * **Faz R.3C.2 — `branchAccess` claim added.** Shaped identically to
 * `roles` (`Record<organizationId, string[]>`) for the same reason: a
 * staff member's `memberships` document already tracks per-organization
 * `branchAccess` (a plain array of explicit branch ids — this model has no
 * wildcard/"all branches" or role-based bypass semantics, not even for
 * `admin`/`tenantOwner`; [bootstrapFirstAdminAccount] itself starts with
 * `branchAccess: []`), so the claim mirrors that shape exactly rather than
 * inventing a new one. Every value here comes from Firestore, never from
 * `request.data` — the caller-facing callables in this file never accept a
 * branch id as an authority for their own effect, only as the *target* of
 * an already-authorized grant/revoke.
 */
async function resyncClaimsForUid(uid: string): Promise<void> {
  const db = getFirestore();
  const snapshot = await db.collection("memberships").where("uid", "==", uid).get();

  const organizationAccess: string[] = [];
  const roles: Record<string, MembershipRole[]> = {};
  const branchAccess: Record<string, string[]> = {};

  for (const doc of snapshot.docs) {
    const data = doc.data() as MembershipDoc;
    if (data.status !== "active") continue;
    organizationAccess.push(data.organizationId);
    roles[data.organizationId] = data.roles;
    branchAccess[data.organizationId] = data.branchAccess;
  }

  await getAuth().setCustomUserClaims(uid, { organizationAccess, roles, branchAccess });
}

/**
 * Self-service, zero-trust claims bootstrap/sync — Faz R.3A D1. The
 * caller supplies nothing: every claim value is derived entirely from
 * their own *active* `memberships` documents, looked up by
 * `request.auth.uid`, never by any client-supplied identifier. A caller
 * with zero active memberships (never registered, or every membership
 * suspended/archived) receives empty claims (`organizationAccess: []`,
 * `roles: {}`) — the correct, safe result, not an error: this is exactly
 * how a disabled/inactive staff member's *derivation* loses effective
 * authorization the next time they sync (the client must then force a
 * token refresh — `getIdToken(true)` — before the new/cleared claims take
 * effect on their next callable call; an already-issued ID token remains
 * valid until its own natural expiry regardless, an inherent property of
 * Firebase custom claims this callable cannot and does not attempt to
 * override).
 */
export const syncOwnStaffClaims = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    await resyncClaimsForUid(request.auth.uid);
    return { synced: true };
  },
);

/**
 * The one self-authorizing exception — creates exactly one `active`
 * `admin` membership for `request.auth.uid` under [organizationId], and
 * only when no membership document exists yet for that organization at
 * all (any status) — mirrors `BootstrapFirstAdminAccount.dart`'s "only
 * when the repository is currently empty" guard, scoped per-organization
 * here rather than globally, since this backend is multi-tenant-capable
 * even though the app itself remains single-tenant-in-practice today.
 */
export const bootstrapFirstAdminAccount = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");

    const db = getFirestore();
    const existingForOrg = await db
      .collection("memberships")
      .where("organizationId", "==", organizationId)
      .limit(1)
      .get();
    if (!existingForOrg.empty) {
      throw new HttpsError(
        "failed-precondition",
        `Organization "${organizationId}" already has at least one membership — bootstrap is only available before the first one exists.`,
      );
    }

    const uid = request.auth.uid;
    const now = new Date();
    const doc: MembershipDoc = {
      organizationId,
      uid,
      roles: ["admin"],
      branchAccess: [],
      restaurantAccess: [],
      status: "active",
      createdAt: now,
      updatedAt: now,
      version: 1,
    };
    await db.collection("memberships").doc(membershipId(organizationId, uid)).set(doc);
    await resyncClaimsForUid(uid);

    return { organizationId, uid, bootstrapped: true };
  },
);

/**
 * Registers a new, roleless membership for the Firebase Auth account
 * identified by [email] — mirrors `RegisterStaffMember.dart`'s own "starts
 * with no roles at all; a separate role grant is required before sign-in
 * is meaningful" shape. Idempotent: registering an email that already has
 * a membership for this organization returns the existing document
 * rather than erroring or duplicating it.
 */
export const registerStaffMember = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const email = requireNonEmptyString(data.email, "email");

    requireStaffPermission(request, organizationId, "manageStaffAccounts");

    let uid: string;
    try {
      uid = (await getAuth().getUserByEmail(email)).uid;
    } catch {
      throw new HttpsError("not-found", "No Firebase Auth account exists for this email.");
    }

    const db = getFirestore();
    const ref = db.collection("memberships").doc(membershipId(organizationId, uid));
    const existing = await ref.get();
    if (existing.exists) {
      return { organizationId, uid, registered: false, alreadyExisted: true };
    }

    const now = new Date();
    const doc: MembershipDoc = {
      organizationId,
      uid,
      roles: [],
      branchAccess: [],
      restaurantAccess: [],
      status: "active",
      createdAt: now,
      updatedAt: now,
      version: 1,
    };
    await ref.set(doc);

    return { organizationId, uid, registered: true, alreadyExisted: false };
  },
);

function roleGrantPermission(role: MembershipRole): "manageStaffAdminRole" | "manageStaffRoles" {
  return role === "admin" ? "manageStaffAdminRole" : "manageStaffRoles";
}

async function loadMembershipOrThrow(
  db: FirebaseFirestore.Firestore,
  organizationId: string,
  targetUid: string,
): Promise<FirebaseFirestore.DocumentReference> {
  const ref = db.collection("memberships").doc(membershipId(organizationId, targetUid));
  const doc = await ref.get();
  if (!doc.exists) {
    throw new HttpsError("not-found", "No membership found for this account in this organization.");
  }
  return ref;
}

/**
 * Grants [role] to [targetUid]'s membership — role-scoped authorization
 * (`manageStaffAdminRole` for granting `admin` itself, `manageStaffRoles`
 * for anything else) and "no self-promotion" (structural, checked before
 * the permission check, mirroring `AssignStaffRole.dart` exactly — an
 * admin granting themselves a role they don't yet hold is blocked the
 * same way a manager attempting the same thing would be).
 */
export const assignStaffRole = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const targetUid = requireNonEmptyString(data.targetUid, "targetUid");
    const role = requireNonEmptyString(data.role, "role") as MembershipRole;
    if (!VALID_ROLES.includes(role)) invalid(`role must be one of: ${VALID_ROLES.join(", ")}.`);

    if (request.auth && targetUid === request.auth.uid) {
      throw new HttpsError("permission-denied", "A staff member cannot grant themselves a role.");
    }

    requireStaffPermission(request, organizationId, roleGrantPermission(role));

    const db = getFirestore();
    const ref = await loadMembershipOrThrow(db, organizationId, targetUid);
    const doc = (await ref.get()).data() as MembershipDoc;
    const roles = doc.roles.includes(role) ? doc.roles : [...doc.roles, role];
    await ref.update({ roles, updatedAt: new Date(), version: (doc.version ?? 1) + 1 });
    await resyncClaimsForUid(targetUid);

    return { organizationId, targetUid, role, granted: true };
  },
);

/** The revoke-side sibling of [assignStaffRole] — a no-op if [role] wasn't held. */
export const revokeStaffRole = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const targetUid = requireNonEmptyString(data.targetUid, "targetUid");
    const role = requireNonEmptyString(data.role, "role") as MembershipRole;
    if (!VALID_ROLES.includes(role)) invalid(`role must be one of: ${VALID_ROLES.join(", ")}.`);

    if (request.auth && targetUid === request.auth.uid) {
      throw new HttpsError("permission-denied", "A staff member cannot revoke their own role.");
    }

    requireStaffPermission(request, organizationId, roleGrantPermission(role));

    const db = getFirestore();
    const ref = await loadMembershipOrThrow(db, organizationId, targetUid);
    const doc = (await ref.get()).data() as MembershipDoc;
    if (!doc.roles.includes(role)) {
      return { organizationId, targetUid, role, revoked: false };
    }
    const roles = doc.roles.filter((r) => r !== role);
    await ref.update({ roles, updatedAt: new Date(), version: (doc.version ?? 1) + 1 });
    await resyncClaimsForUid(targetUid);

    return { organizationId, targetUid, role, revoked: true };
  },
);

/** Grants [targetUid]'s membership access to [branchId] — `manageStaffBranchAccess`. */
export const grantStaffBranchAccess = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const targetUid = requireNonEmptyString(data.targetUid, "targetUid");
    const branchId = requireNonEmptyString(data.branchId, "branchId");

    requireStaffPermission(request, organizationId, "manageStaffBranchAccess");

    const db = getFirestore();
    const ref = await loadMembershipOrThrow(db, organizationId, targetUid);
    const doc = (await ref.get()).data() as MembershipDoc;
    const branchAccess = doc.branchAccess.includes(branchId)
      ? doc.branchAccess
      : [...doc.branchAccess, branchId];
    await ref.update({ branchAccess, updatedAt: new Date(), version: (doc.version ?? 1) + 1 });
    await resyncClaimsForUid(targetUid);

    return { organizationId, targetUid, branchId, granted: true };
  },
);

/** The revoke-side sibling of [grantStaffBranchAccess] — a no-op if [branchId] wasn't granted. */
export const revokeStaffBranchAccess = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const targetUid = requireNonEmptyString(data.targetUid, "targetUid");
    const branchId = requireNonEmptyString(data.branchId, "branchId");

    requireStaffPermission(request, organizationId, "manageStaffBranchAccess");

    const db = getFirestore();
    const ref = await loadMembershipOrThrow(db, organizationId, targetUid);
    const doc = (await ref.get()).data() as MembershipDoc;
    if (!doc.branchAccess.includes(branchId)) {
      return { organizationId, targetUid, branchId, revoked: false };
    }
    const branchAccess = doc.branchAccess.filter((b) => b !== branchId);
    await ref.update({ branchAccess, updatedAt: new Date(), version: (doc.version ?? 1) + 1 });
    await resyncClaimsForUid(targetUid);

    return { organizationId, targetUid, branchId, revoked: true };
  },
);

/**
 * Sets [targetUid]'s membership `status` — `manageStaffAccounts`.
 * `archived` is terminal, mirroring `SetStaffMemberStatus.dart`: an
 * already-`archived` membership can never be targeted again, by this or
 * any other status transition.
 */
export const setStaffMemberStatus = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const targetUid = requireNonEmptyString(data.targetUid, "targetUid");
    const status = requireNonEmptyString(data.status, "status") as MembershipStatus;
    if (!VALID_STATUSES.includes(status)) {
      invalid(`status must be one of: ${VALID_STATUSES.join(", ")}.`);
    }

    requireStaffPermission(request, organizationId, "manageStaffAccounts");

    const db = getFirestore();
    const ref = await loadMembershipOrThrow(db, organizationId, targetUid);
    const doc = (await ref.get()).data() as MembershipDoc;
    if (doc.status === "archived") {
      throw new HttpsError("failed-precondition", "This membership is archived — its status can no longer change.");
    }

    await ref.update({ status, updatedAt: new Date(), version: (doc.version ?? 1) + 1 });
    await resyncClaimsForUid(targetUid);

    return { organizationId, targetUid, status, updated: true };
  },
);
