import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { requirePlatformMember } from "./platformAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";

/**
 * AP-2 Stage B — the real writer for the EXISTING `entitlements` collection
 * (`firestore.rules`: `allow write: if false`, no writer until now — the
 * AP-0-found "rule with no writer" gap, closed directly, not via a new
 * collection). Mirrors the Dart `EntitlementGrant`/`EntitlementModule`/
 * `EntitlementScopeType` domain (`lib/features/entitlements/domain/**`,
 * Phase 7/8, ADR-024/ADR-025) — this file does not redesign that model,
 * it gives it a real backend. `EntitlementStatus` gains `grace`/
 * `suspended` here (Correction #8) — the Dart enum currently has only
 * `active`/`trial`/`expired`/`revoked`; extending it to match is Flutter
 * wiring work, tracked as remaining scope, not done in this file.
 *
 * **Entitlements are ENTIRELY platform-controlled** — every callable here
 * requires `requirePlatformMember`. There is no tenant-scoped grant path
 * at all, which is what makes "Tenant Admin kendisine entitlement veremez
 * veya grace süresini uzatamaz" true structurally, not by a runtime check
 * that could be forgotten.
 */

export type EntitlementModule =
  | "smartRestaurantSetup" | "menuImport" | "inventory" | "recipes" | "nutrition" | "allergens"
  | "purchasing" | "suppliers" | "costing" | "profitability" | "advancedReporting"
  | "qrMenu" | "reservations" | "crm" | "loyalty" | "pos" | "kds" | "courier" | "marketplace"
  | "payments" | "ai";
export type EntitlementScopeType = "organization" | "restaurant" | "branch";
export type EntitlementStatus = "trial" | "active" | "grace" | "suspended" | "expired" | "revoked";

const VALID_MODULES: readonly EntitlementModule[] = [
  "smartRestaurantSetup", "menuImport", "inventory", "recipes", "nutrition", "allergens",
  "purchasing", "suppliers", "costing", "profitability", "advancedReporting",
  "qrMenu", "reservations", "crm", "loyalty", "pos", "kds", "courier", "marketplace",
  "payments", "ai",
];
const VALID_SCOPE_TYPES: readonly EntitlementScopeType[] = ["organization", "restaurant", "branch"];
const GRACE_PERIOD_DAYS = 3;

export interface EntitlementDoc {
  organizationId: string;
  scopeType: EntitlementScopeType;
  scopeId: string;
  module: EntitlementModule;
  status: EntitlementStatus;
  contractStartsAt: Timestamp | null;
  contractEndsAt: Timestamp | null;
  graceStartedAt: Timestamp | null;
  graceEndsAt: Timestamp | null;
  postGraceDisabledModules: EntitlementModule[];
  grantedByPlatformUid: string;
  grantedAt: Timestamp;
  updatedAt: Timestamp;
  version: number;
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) invalid(`${field} is required.`);
  return value as string;
}
function entitlementId(organizationId: string, scopeType: EntitlementScopeType, scopeId: string, module: EntitlementModule): string {
  return `${organizationId}_${scopeType}_${scopeId}_${module}`;
}

/** Grants (creates, or idempotently returns) an entitlement — Platform Owner/Administrator only. */
export const grantEntitlement = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformMember(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const scopeType = requireNonEmptyString(data.scopeType, "scopeType") as EntitlementScopeType;
    if (!VALID_SCOPE_TYPES.includes(scopeType)) invalid(`scopeType must be one of: ${VALID_SCOPE_TYPES.join(", ")}.`);
    const scopeId = requireNonEmptyString(data.scopeId, "scopeId");
    const module = requireNonEmptyString(data.module, "module") as EntitlementModule;
    if (!VALID_MODULES.includes(module)) invalid(`module must be one of: ${VALID_MODULES.join(", ")}.`);
    const initialStatus = (data.initialStatus as string) === "active" ? "active" : "trial";
    const contractStartsAt = typeof data.contractStartsAtIso === "string" ? Timestamp.fromDate(new Date(data.contractStartsAtIso)) : null;
    const contractEndsAt = typeof data.contractEndsAtIso === "string" ? Timestamp.fromDate(new Date(data.contractEndsAtIso)) : null;

    const db = getFirestore();
    const id = entitlementId(organizationId, scopeType, scopeId, module);
    const ref = db.collection("entitlements").doc(id);
    const existing = await ref.get();
    if (existing.exists) {
      return { entitlementId: id, status: (existing.data() as EntitlementDoc).status, alreadyGranted: true };
    }

    const correlationId = generateCorrelationId();
    const clientRequestId = sanitizeClientRequestId(data.clientRequestId);
    const now = Timestamp.now();

    await db.runTransaction(async (tx) => {
      const doc: EntitlementDoc = {
        organizationId, scopeType, scopeId, module,
        status: initialStatus as EntitlementStatus,
        contractStartsAt, contractEndsAt,
        graceStartedAt: null, graceEndsAt: null, postGraceDisabledModules: [],
        grantedByPlatformUid: request.auth!.uid, grantedAt: now, updatedAt: now, version: 1,
      };
      tx.set(ref, doc);
      writeAuditEvent({
        tx, db,
        eventId: `${id}-granted-v1`,
        organizationId, type: "entitlement.granted", targetRef: ref.path,
        newValue: initialStatus, actorType: "platform", actorUid: request.auth!.uid,
        correlationId, clientRequestId, now,
      });
    });

    return { entitlementId: id, status: initialStatus, alreadyGranted: false, correlationId };
  },
);

/** Renews an entitlement's contract period — clears any grace/suspended state, sets status "active". */
export const renewEntitlement = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformMember(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const id = requireNonEmptyString(data.entitlementId, "entitlementId");
    const contractEndsAt = typeof data.contractEndsAtIso === "string" ? Timestamp.fromDate(new Date(data.contractEndsAtIso)) : null;
    if (!contractEndsAt) invalid("contractEndsAtIso is required.");

    const db = getFirestore();
    const correlationId = generateCorrelationId();
    const now = Timestamp.now();

    const result = await db.runTransaction(async (tx) => {
      const ref = db.collection("entitlements").doc(id);
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "No entitlement grant found for this id.");
      const current = snap.data() as EntitlementDoc;
      if (current.status === "revoked") {
        throw new HttpsError("failed-precondition", "A revoked entitlement cannot be renewed — grant a new one.");
      }
      const nextVersion = current.version + 1;
      tx.update(ref, {
        status: "active" as EntitlementStatus,
        contractEndsAt,
        graceStartedAt: null,
        graceEndsAt: null,
        updatedAt: now,
        version: nextVersion,
      });
      writeAuditEvent({
        tx, db, eventId: `${id}-renewed-v${nextVersion}`,
        organizationId: current.organizationId, type: "entitlement.renewed", targetRef: ref.path,
        previousValue: current.status, newValue: "active", actorType: "platform", actorUid: request.auth!.uid,
        correlationId, now,
      });
      return { version: nextVersion };
    });

    return { entitlementId: id, status: "active", version: result.version, correlationId };
  },
);

/**
 * Suspends an entitlement — always enters a fixed 3-day grace period
 * first (Correction #8: "Sabit üç günlük grace süresi"), never an
 * immediate hard suspend. [postGraceDisabledModules] is the Platform-Owner
 * -selected shutdown policy — which modules actually go dark once grace
 * expires; defaults to just this module if not specified.
 */
export const suspendEntitlement = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformMember(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const id = requireNonEmptyString(data.entitlementId, "entitlementId");
    const reasonMessage = requireNonEmptyString(data.reasonMessage, "reasonMessage");
    const requestedDisabled = Array.isArray(data.postGraceDisabledModules) ? (data.postGraceDisabledModules as unknown[]) : [];
    const postGraceDisabledModules = requestedDisabled.filter((m): m is EntitlementModule =>
      typeof m === "string" && VALID_MODULES.includes(m as EntitlementModule),
    );

    const db = getFirestore();
    const correlationId = generateCorrelationId();
    const now = Timestamp.now();

    const result = await db.runTransaction(async (tx) => {
      const ref = db.collection("entitlements").doc(id);
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "No entitlement grant found for this id.");
      const current = snap.data() as EntitlementDoc;
      if (current.status === "revoked") {
        throw new HttpsError("failed-precondition", "A revoked entitlement is already terminal.");
      }
      const nextVersion = current.version + 1;
      const graceEndsAt = Timestamp.fromMillis(now.toMillis() + GRACE_PERIOD_DAYS * 24 * 60 * 60_000);
      tx.update(ref, {
        status: "grace" as EntitlementStatus,
        graceStartedAt: now,
        graceEndsAt,
        postGraceDisabledModules: postGraceDisabledModules.length > 0 ? postGraceDisabledModules : [current.module],
        updatedAt: now,
        version: nextVersion,
      });
      writeAuditEvent({
        tx, db, eventId: `${id}-suspended-v${nextVersion}`,
        organizationId: current.organizationId, type: "entitlement.suspended", targetRef: ref.path,
        previousValue: current.status, newValue: "grace", actorType: "platform", actorUid: request.auth!.uid,
        reasonMessage, correlationId, now,
      });
      return { version: nextVersion, graceEndsAt };
    });

    return { entitlementId: id, status: "grace", graceEndsAt: result.graceEndsAt.toDate().toISOString(), version: result.version, correlationId };
  },
);

/** Immediate, terminal revocation — no grace period. */
export const revokeEntitlement = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformMember(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const id = requireNonEmptyString(data.entitlementId, "entitlementId");
    const reasonMessage = requireNonEmptyString(data.reasonMessage, "reasonMessage");

    const db = getFirestore();
    const correlationId = generateCorrelationId();
    const now = Timestamp.now();

    const result = await db.runTransaction(async (tx) => {
      const ref = db.collection("entitlements").doc(id);
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "No entitlement grant found for this id.");
      const current = snap.data() as EntitlementDoc;
      if (current.status === "revoked") {
        return { version: current.version, alreadyRevoked: true };
      }
      const nextVersion = current.version + 1;
      tx.update(ref, { status: "revoked" as EntitlementStatus, updatedAt: now, version: nextVersion });
      writeAuditEvent({
        tx, db, eventId: `${id}-revoked-v${nextVersion}`,
        organizationId: current.organizationId, type: "entitlement.revoked", targetRef: ref.path,
        previousValue: current.status, newValue: "revoked", actorType: "platform", actorUid: request.auth!.uid,
        reasonMessage, correlationId, now,
      });
      return { version: nextVersion, alreadyRevoked: false };
    });

    return { entitlementId: id, status: "revoked", ...result, correlationId };
  },
);

/** Sweeps `grace` entitlements past `graceEndsAt` -> `suspended` (terminal until renewed). Mirrors `sweepExpiredApprovalRequests`'s own callable-not-yet-scheduled shape. */
export const sweepExpiredEntitlementGracePeriods = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();
    const graceSnap = await db.collection("entitlements").where("status", "==", "grace").get();
    let suspended = 0;
    for (const doc of graceSnap.docs) {
      const record = doc.data() as EntitlementDoc;
      if (!record.graceEndsAt || record.graceEndsAt.toMillis() >= now.toMillis()) continue;
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        const current = snap.data() as EntitlementDoc;
        if (current.status !== "grace") return;
        tx.update(doc.ref, { status: "suspended" as EntitlementStatus, updatedAt: now, version: current.version + 1 });
        writeAuditEvent({
          tx, db, eventId: `${doc.id}-grace-expired-v${current.version + 1}`,
          organizationId: current.organizationId, type: "entitlement.graceExpired", targetRef: doc.ref.path,
          previousValue: "grace", newValue: "suspended", actorType: "system", actorUid: null,
          correlationId: generateCorrelationId(), now,
        });
      });
      suspended += 1;
    }
    return { suspended };
  },
);

/**
 * Server-side entitlement check for a specific module — used by other AP-2
 * commands (`trustedDevice.ts`'s POS/KDS-capability registration) so a
 * client's `ModuleEntitlementGate` (UX-only) is never the only barrier.
 * `active`/`trial` count as entitled; `grace` also still counts (the grace
 * period exists precisely so the module keeps working during it) —
 * `suspended`/`expired`/`revoked` never do.
 */
export async function requireModuleEntitlement(organizationId: string, module: EntitlementModule): Promise<void> {
  const db = getFirestore();
  const ref = db.collection("entitlements").doc(entitlementId(organizationId, "organization", organizationId, module));
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", `Module "${module}" is not entitled for this organization.`);
  }
  const data = snap.data() as EntitlementDoc;
  const entitled = data.status === "active" || data.status === "trial" || data.status === "grace";
  if (!entitled) {
    throw new HttpsError("failed-precondition", `Module "${module}" is not currently entitled (status: ${data.status}).`);
  }
}
