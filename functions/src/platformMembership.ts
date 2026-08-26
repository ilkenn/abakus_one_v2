import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { requirePlatformMember } from "./platformAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";

/**
 * AP-2 Stage B — the real writer for the EXISTING `platformMembers`
 * collection (`firestore.rules` line ~187: `allow read: if isPlatformMember()
 * && request.auth.uid == platformMemberId; allow write: if false;` — already
 * present since an earlier phase, never given a Cloud Function writer until
 * now). Reuses `platformAuthorization.ts`'s `requirePlatformMember` claims
 * check unmodified.
 *
 * **REUSE, not a parallel model**: `lib/features/platform/**` already
 * defines a full `PlatformMember`/`PlatformRole`/`PlatformActorSession`
 * domain (Phase 8, ADR-025) with an in-memory-only repository today. This
 * file's document shape mirrors that Dart `PlatformMember` model
 * (`displayName`/`roles`/`status`/`authUid`) — a future
 * `FirebasePlatformMemberRepository` can map onto it directly. The doc id
 * is the Firebase Auth `uid` (confirmed by the existing rule's own
 * `request.auth.uid == platformMemberId` check), not a sequential id — the
 * one point of intentional divergence from the Dart model's
 * `PlatformMemberIdGenerator`, forced by the pre-existing rule shape this
 * file must satisfy, not invented here.
 *
 * **`lib/features/platform/application/use_cases/
 * bootstrap_first_platform_owner_account.dart` is DO_NOT_USE for
 * production wiring, as-is.** It self-registers a new Firebase Auth
 * email/password account and creates a `PlatformMember` from inside the
 * running app, gated only by "the repository is currently empty" — exactly
 * the "tekrar tekrar kullanılabilir açık backdoor" the corrected AP-2 spec
 * explicitly forbids if ever pointed at a real Firestore-backed repository.
 * The real, first-ever Platform Owner is created only by
 * `functions/scripts/bootstrap_platform_owner.mjs`, an out-of-band Admin
 * SDK script requiring real GCP project credentials, never a callable path.
 */

export type PlatformRoleName = "platformAdministrator" | "platformOwner";
export type PlatformMemberStatus = "active" | "suspended" | "archived";

const VALID_PLATFORM_ROLES: readonly PlatformRoleName[] = ["platformAdministrator", "platformOwner"];

interface PlatformMemberDoc {
  displayName: string;
  roles: PlatformRoleName[];
  status: PlatformMemberStatus;
  authUid: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  version: number;
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

function highestRole(roles: readonly PlatformRoleName[]): PlatformRoleName | null {
  if (roles.includes("platformOwner")) return "platformOwner";
  if (roles.includes("platformAdministrator")) return "platformAdministrator";
  return null;
}

/**
 * Rebuilds the `platformRole` custom claim for [uid] from their own
 * `platformMembers/{uid}` document — the platform-tier mirror of
 * `staffMembership.ts`'s `resyncClaimsForUid`. Only the single highest
 * role name is ever carried in the claim, never the full `roles` array or
 * any derived permission set — Correction #1's "no unbounded permission
 * map in claims" applies here too, even though this is a role claim, not a
 * permission override: `requirePlatformMember` only ever checks this one
 * bounded string.
 */
async function resyncPlatformClaimsForUid(uid: string): Promise<void> {
  const db = getFirestore();
  const snap = await db.collection("platformMembers").doc(uid).get();
  if (!snap.exists) {
    await getAuth().setCustomUserClaims(uid, { platformRole: null });
    return;
  }
  const data = snap.data() as PlatformMemberDoc;
  const role = data.status === "active" ? highestRole(data.roles) : null;
  await getAuth().setCustomUserClaims(uid, { platformRole: role });
}

/** Self-service claims sync — mirrors `syncOwnStaffClaims` exactly, one tier up. */
export const syncOwnPlatformClaims = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    await resyncPlatformClaimsForUid(request.auth.uid);
    return { synced: true };
  },
);

/**
 * Grants [role] to [targetUid]'s `platformMembers` document — creates the
 * document on first grant. Self-grant structurally forbidden. Granting
 * `platformOwner` itself requires the CALLER to already hold
 * `platformOwner` (never a mere `platformAdministrator`) — mirrors
 * `staffMembership.ts`'s admin-role-requires-admin-tier split one level up.
 * [targetUid] must be a real Firebase Auth account (verified via
 * `getAuth().getUser`) — mirrors `registerStaffMember`'s
 * `getUserByEmail`-existence check.
 */
export const grantPlatformRole = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformMember(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const targetUid = requireNonEmptyString(data.targetUid, "targetUid");
    const role = requireNonEmptyString(data.role, "role") as PlatformRoleName;
    if (!VALID_PLATFORM_ROLES.includes(role)) {
      invalid(`role must be one of: ${VALID_PLATFORM_ROLES.join(", ")}.`);
    }

    if (request.auth!.uid === targetUid) {
      throw new HttpsError("permission-denied", "A platform member cannot grant themselves a role.");
    }
    if (role === "platformOwner" && request.auth!.token?.platformRole !== "platformOwner") {
      throw new HttpsError(
        "permission-denied",
        "Only a Platform Owner may grant the Platform Owner role.",
      );
    }

    try {
      await getAuth().getUser(targetUid);
    } catch {
      throw new HttpsError("not-found", "No Firebase Auth account exists for this uid.");
    }

    const db = getFirestore();
    const correlationId = generateCorrelationId();
    const clientRequestId = sanitizeClientRequestId(data.clientRequestId);
    const now = Timestamp.now();

    const result = await db.runTransaction(async (tx) => {
      const ref = db.collection("platformMembers").doc(targetUid);
      const snap = await tx.get(ref);
      const existing = snap.exists ? (snap.data() as PlatformMemberDoc) : null;
      const previousRoles = existing?.roles ?? [];
      const nextRoles = previousRoles.includes(role) ? previousRoles : [...previousRoles, role];
      const nextVersion = (existing?.version ?? 0) + 1;

      const doc: PlatformMemberDoc = {
        displayName: existing?.displayName ?? targetUid,
        roles: nextRoles,
        status: existing?.status ?? "active",
        authUid: targetUid,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        version: nextVersion,
      };
      tx.set(ref, doc);

      writeAuditEvent({
        tx,
        db,
        eventId: `${targetUid}-platform-role-granted-${role}-v${nextVersion}`,
        organizationId: null,
        type: "platform.roleGranted",
        targetRef: ref.path,
        previousValue: previousRoles,
        newValue: nextRoles,
        actorType: "platform",
        actorUid: request.auth!.uid,
        reasonCode: typeof data.reasonCode === "string" ? data.reasonCode : null,
        reasonMessage: typeof data.reasonMessage === "string" ? data.reasonMessage : null,
        correlationId,
        clientRequestId,
        now,
      });

      return { version: nextVersion };
    });

    await resyncPlatformClaimsForUid(targetUid);
    return { targetUid, role, granted: true, version: result.version, correlationId };
  },
);

/** The revoke-side sibling of [grantPlatformRole] — a no-op if [role] wasn't held. Self-revoke forbidden. */
export const revokePlatformRole = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformMember(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const targetUid = requireNonEmptyString(data.targetUid, "targetUid");
    const role = requireNonEmptyString(data.role, "role") as PlatformRoleName;
    if (!VALID_PLATFORM_ROLES.includes(role)) {
      invalid(`role must be one of: ${VALID_PLATFORM_ROLES.join(", ")}.`);
    }

    if (request.auth!.uid === targetUid) {
      throw new HttpsError("permission-denied", "A platform member cannot revoke their own role.");
    }
    if (role === "platformOwner" && request.auth!.token?.platformRole !== "platformOwner") {
      throw new HttpsError(
        "permission-denied",
        "Only a Platform Owner may revoke the Platform Owner role.",
      );
    }

    const db = getFirestore();
    const correlationId = generateCorrelationId();
    const clientRequestId = sanitizeClientRequestId(data.clientRequestId);
    const now = Timestamp.now();

    const result = await db.runTransaction(async (tx) => {
      const ref = db.collection("platformMembers").doc(targetUid);
      const snap = await tx.get(ref);
      if (!snap.exists) {
        return { revoked: false, version: null as number | null };
      }
      const existing = snap.data() as PlatformMemberDoc;
      if (!existing.roles.includes(role)) {
        return { revoked: false, version: existing.version };
      }
      const nextRoles = existing.roles.filter((r) => r !== role);
      const nextVersion = existing.version + 1;
      tx.update(ref, { roles: nextRoles, updatedAt: now, version: nextVersion });

      writeAuditEvent({
        tx,
        db,
        eventId: `${targetUid}-platform-role-revoked-${role}-v${nextVersion}`,
        organizationId: null,
        type: "platform.roleRevoked",
        targetRef: ref.path,
        previousValue: existing.roles,
        newValue: nextRoles,
        actorType: "platform",
        actorUid: request.auth!.uid,
        reasonCode: typeof data.reasonCode === "string" ? data.reasonCode : null,
        reasonMessage: typeof data.reasonMessage === "string" ? data.reasonMessage : null,
        correlationId,
        clientRequestId,
        now,
      });

      return { revoked: true, version: nextVersion };
    });

    if (result.revoked) {
      await resyncPlatformClaimsForUid(targetUid);
    }
    return { targetUid, role, revoked: result.revoked, version: result.version, correlationId };
  },
);
