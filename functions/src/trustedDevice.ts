import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { createHash, randomBytes, verify as cryptoVerify } from "crypto";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import { createApprovalRequest } from "./remoteApproval";
import type { ActionHandlerParams, ActionHandlerResult } from "./remoteApproval";
import { requireModuleEntitlement } from "./entitlementAdmin";

/**
 * AP-2 Stage B — the trusted-device ONLINE foundation (`docs/
 * admin_pos_architecture.md` §12). Offline lease execution is explicitly
 * AP-4 scope; nothing here blocks that data model, but nothing here
 * implements it either.
 *
 * **Correction #4 — trust tiers, honestly, never faked**:
 * `HARDWARE_ATTESTED` requires a real platform attestation integration
 * (Play Integrity / App Attest) that does not exist yet — no registration
 * resolves to it in AP-2, regardless of platform or client claim. Only
 * `android`/`ios`/`windows`/`macos` are even eligible for
 * `PLATFORM_PROTECTED` (an OS-secure-storage-backed asymmetric key, proven
 * only by a real challenge-response signature — never a bare device
 * identifier). `web` always resolves `UNSUPPORTED_OR_UNTRUSTED` this phase
 * — no WebAuthn/enterprise-device-binding integration exists, so nothing
 * here pretends a browser has OS-level secure key storage.
 *
 * **Correction #5 — challenge/session model**: `deviceChallenges` are
 * single-use (deleted/marked consumed inside the same transaction that
 * verifies them) and short-TTL. `deviceSessions` are never directly
 * readable/writable by any client via Firestore rules (`allow read, write:
 * if false`) — a device learns its own session only from the direct
 * response of `issueDeviceSession`/`renewDeviceSession`, and every
 * device-restricted callable re-verifies the session server-side
 * ([requireActiveDeviceSession]) rather than trusting a client-asserted
 * token's mere presence.
 */

export type DeviceCapability = "POS" | "KDS" | "PRINTER_CONTROLLER";
export type DeviceStatus = "pending" | "active" | "suspended" | "revoked" | "retired";
export type DeviceTrustTier = "HARDWARE_ATTESTED" | "PLATFORM_PROTECTED" | "UNSUPPORTED_OR_UNTRUSTED";
export type DevicePlatform = "android" | "ios" | "windows" | "macos" | "web";
export type SignatureAlgorithm = "RSA-SHA256" | "ed25519";

const VALID_CAPABILITIES: readonly DeviceCapability[] = ["POS", "KDS", "PRINTER_CONTROLLER"];
const VALID_PLATFORMS: readonly DevicePlatform[] = ["android", "ios", "windows", "macos", "web"];
const PLATFORM_PROTECTED_ELIGIBLE: ReadonlySet<DevicePlatform> = new Set(["android", "ios", "windows", "macos"]);
const CHALLENGE_TTL_SECONDS = 120;
const SESSION_DURATION_SECONDS = 12 * 60 * 60;

interface DeviceRegistrationDoc {
  organizationId: string;
  branchId: string;
  deviceId: string;
  platform: DevicePlatform;
  publicKeyPem: string;
  publicKeyFingerprint: string;
  signatureAlgorithm: SignatureAlgorithm;
  capabilities: DeviceCapability[];
  status: DeviceStatus;
  trustTier: DeviceTrustTier;
  registeredByUid: string;
  registeredAt: Timestamp;
  activatedAt: Timestamp | null;
  lastSeenAt: Timestamp | null;
  revokedAt: Timestamp | null;
  revokedReason: string | null;
  version: number;
}

interface DeviceChallengeDoc {
  deviceId: string;
  nonce: string;
  purpose: "issue" | "renew";
  createdAt: Timestamp;
  expiresAt: Timestamp;
  consumedAt: Timestamp | null;
}

interface DeviceSessionDoc {
  deviceId: string;
  organizationId: string;
  branchId: string;
  status: "active" | "expired" | "revoked";
  issuedAt: Timestamp;
  expiresAt: Timestamp;
  lastStaffUid: string | null;
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) invalid(`${field} is required.`);
  return value as string;
}
function fingerprintOf(publicKeyPem: string): string {
  return createHash("sha256").update(publicKeyPem).digest("hex");
}
function deviceDocId(organizationId: string, branchId: string, deviceId: string): string {
  return `${organizationId}_${branchId}_${deviceId}`;
}
/** Correction #4 — server-generated, fingerprint-derived; never a client-chosen id used as document authority. */
function deriveServerDeviceId(publicKeyPem: string): string {
  return fingerprintOf(publicKeyPem).slice(0, 24);
}

async function loadDeviceRegistration(
  db: FirebaseFirestore.Firestore,
  organizationId: string,
  branchId: string,
  deviceId: string,
): Promise<{ ref: FirebaseFirestore.DocumentReference; data: DeviceRegistrationDoc }> {
  const ref = db.collection("trustedDeviceRegistrations").doc(deviceDocId(organizationId, branchId, deviceId));
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "No trusted device registration found.");
  }
  return { ref, data: snap.data() as DeviceRegistrationDoc };
}

/**
 * Registers a device — creates (or idempotently returns) a `pending`
 * registration, then immediately creates its own gated approval request
 * (Correction #6: activation is never direct). The requester is recorded
 * as `registeredByUid` so `respondToApprovalRequest`'s self-approval check
 * later blocks them from activating their own request.
 */
export const requestDeviceRegistration = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const branchId = requireNonEmptyString(data.branchId, "branchId");
    const platform = requireNonEmptyString(data.platform, "platform") as DevicePlatform;
    if (!VALID_PLATFORMS.includes(platform)) invalid(`platform must be one of: ${VALID_PLATFORMS.join(", ")}.`);
    const publicKeyPem = requireNonEmptyString(data.publicKeyPem, "publicKeyPem");
    const signatureAlgorithm = requireNonEmptyString(data.signatureAlgorithm, "signatureAlgorithm");
    if (signatureAlgorithm !== "RSA-SHA256" && signatureAlgorithm !== "ed25519") {
      invalid('signatureAlgorithm must be "RSA-SHA256" or "ed25519".');
    }
    const requestedCapabilities = Array.isArray(data.capabilities) ? (data.capabilities as unknown[]) : [];
    const capabilities = requestedCapabilities.filter((c): c is DeviceCapability =>
      typeof c === "string" && VALID_CAPABILITIES.includes(c as DeviceCapability),
    );
    if (capabilities.length === 0) invalid("At least one valid capability is required.");

    requireStaffPermission(request, organizationId, "requestDeviceRegistration");
    requireBranchAccess(request, organizationId, branchId);

    // Correction #8 — a new AP-2 sensitive command re-checks entitlement
    // server-side; the client's own ModuleEntitlementGate is UX-only.
    // Registering a device for POS or KDS capability requires the
    // corresponding module to be currently entitled for the organization.
    if (capabilities.includes("POS")) await requireModuleEntitlement(organizationId, "pos");
    if (capabilities.includes("KDS")) await requireModuleEntitlement(organizationId, "kds");

    const deviceId = deriveServerDeviceId(publicKeyPem);
    const db = getFirestore();
    const ref = db.collection("trustedDeviceRegistrations").doc(deviceDocId(organizationId, branchId, deviceId));
    const existing = await ref.get();
    if (existing.exists) {
      const existingData = existing.data() as DeviceRegistrationDoc;
      return { deviceId, status: existingData.status, trustTier: existingData.trustTier, alreadyRegistered: true };
    }

    // Correction #4 — resolved server-side, never from a client-claimed tier.
    const trustTier: DeviceTrustTier = PLATFORM_PROTECTED_ELIGIBLE.has(platform)
      ? "PLATFORM_PROTECTED"
      : "UNSUPPORTED_OR_UNTRUSTED";

    const now = Timestamp.now();
    const doc: DeviceRegistrationDoc = {
      organizationId,
      branchId,
      deviceId,
      platform,
      publicKeyPem,
      publicKeyFingerprint: fingerprintOf(publicKeyPem),
      signatureAlgorithm,
      capabilities,
      status: "pending",
      trustTier,
      registeredByUid: request.auth.uid,
      registeredAt: now,
      activatedAt: null,
      lastSeenAt: null,
      revokedAt: null,
      revokedReason: null,
      version: 1,
    };
    await ref.set(doc);

    const approval = await createApprovalRequest({
      organizationId,
      branchId,
      actionType: "deviceActivation",
      requestedByActorUid: request.auth.uid,
      targetAggregateRef: ref.path,
      targetAggregateVersion: 1,
      payloadHash: fingerprintOf(publicKeyPem),
    });

    return {
      deviceId,
      status: "pending",
      trustTier,
      alreadyRegistered: false,
      approvalRequestId: approval.requestId,
    };
  },
);

/**
 * The allowlisted `deviceActivation` action handler — called ONLY from
 * inside `remoteApproval.ts`'s own transaction, never directly. Re-verifies
 * the target's CURRENT version against the approval record's
 * `targetAggregateVersion` (stale-target protection) before applying
 * anything — the approval record being `pending` does not by itself prove
 * the target hasn't changed since.
 */
export async function applyDeviceActivation(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now } = params;
  const ref = db.doc(approval.targetAggregateRef);
  const snap = await tx.get(ref);
  if (!snap.exists) {
    throw new HttpsError("not-found", "The device registration no longer exists.");
  }
  const device = snap.data() as DeviceRegistrationDoc;
  if (device.version !== approval.targetAggregateVersion) {
    throw new HttpsError(
      "failed-precondition",
      "The device registration has changed since this approval request was created.",
    );
  }
  if (device.status !== "pending") {
    throw new HttpsError("failed-precondition", `Device is already "${device.status}" — cannot activate.`);
  }
  const nextVersion = device.version + 1;
  tx.update(ref, { status: "active" as DeviceStatus, activatedAt: now, version: nextVersion });
  return { newValue: "active" };
}

/**
 * Issues a fresh, single-use challenge for [deviceId] — the first half of
 * proof-of-possession. Never callable for a non-`active` device.
 */
export const requestDeviceChallenge = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const branchId = requireNonEmptyString(data.branchId, "branchId");
    const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
    const purpose = requireNonEmptyString(data.purpose, "purpose");
    if (purpose !== "issue" && purpose !== "renew") invalid('purpose must be "issue" or "renew".');

    const { data: device } = await loadDeviceRegistration(getFirestore(), organizationId, branchId, deviceId);
    if (device.status !== "active") {
      throw new HttpsError("failed-precondition", `Device is "${device.status}" — not eligible for a session.`);
    }

    const db = getFirestore();
    const now = Timestamp.now();
    const challengeRef = db.collection("deviceChallenges").doc();
    const nonce = randomBytes(32).toString("base64url");
    const challenge: DeviceChallengeDoc = {
      deviceId,
      nonce,
      purpose: purpose as "issue" | "renew",
      createdAt: now,
      expiresAt: Timestamp.fromMillis(now.toMillis() + CHALLENGE_TTL_SECONDS * 1000),
      consumedAt: null,
    };
    await challengeRef.set(challenge);

    return { challengeId: challengeRef.id, nonce, expiresAt: challenge.expiresAt.toDate().toISOString() };
  },
);

function verifySignature(algorithm: SignatureAlgorithm, publicKeyPem: string, nonce: string, signatureBase64: string): boolean {
  try {
    const signature = Buffer.from(signatureBase64, "base64");
    const data = Buffer.from(nonce, "utf8");
    if (algorithm === "ed25519") {
      return cryptoVerify(null, data, publicKeyPem, signature);
    }
    return cryptoVerify("RSA-SHA256", data, publicKeyPem, signature);
  } catch {
    return false;
  }
}

/**
 * Consumes a challenge (single-use, transactionally) and, if the signature
 * verifies against the device's stored public key, issues a short-lived
 * `deviceSessions` document — returned directly in this callable's
 * response (never readable via a client Firestore query; Correction #5).
 * Requires BOTH a valid staff session (this callable's own auth check)
 * AND the device's own cryptographic proof — device-restricted commands
 * built on top of this must additionally check `requireActiveDeviceSession`.
 */
export const issueDeviceSession = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const branchId = requireNonEmptyString(data.branchId, "branchId");
    const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
    const challengeId = requireNonEmptyString(data.challengeId, "challengeId");
    const signature = requireNonEmptyString(data.signature, "signature");

    requireBranchAccess(request, organizationId, branchId);

    const db = getFirestore();
    const { ref: deviceRef, data: device } = await loadDeviceRegistration(db, organizationId, branchId, deviceId);
    if (device.status !== "active") {
      throw new HttpsError("failed-precondition", `Device is "${device.status}" — not eligible for a session.`);
    }
    // Correction #4 — "Full POS/fiscal/offline eligibility yalnız policy'nin
    // izin verdiği trust tier'da çalışır" / "Web operational mode ancak
    // doğrulanmış WebAuthn/enterprise-device binding mimarisi daha sonra
    // kanıtlanırsa açılabilir": an UNSUPPORTED_OR_UNTRUSTED device (today,
    // always `web`, or any platform whose proof-of-possession failed to
    // register as PLATFORM_PROTECTED) can be REGISTERED for visibility/
    // audit, but never issued an operational session. Fails closed.
    if (device.trustTier === "UNSUPPORTED_OR_UNTRUSTED") {
      throw new HttpsError(
        "failed-precondition",
        "This device's platform is not eligible for an operational session (UNSUPPORTED_OR_UNTRUSTED trust tier).",
      );
    }

    const correlationId = generateCorrelationId();
    const clientRequestId = sanitizeClientRequestId(data.clientRequestId);

    const result = await db.runTransaction(async (tx) => {
      const challengeRef = db.collection("deviceChallenges").doc(challengeId);
      const challengeSnap = await tx.get(challengeRef);
      if (!challengeSnap.exists) {
        throw new HttpsError("not-found", "No such challenge.");
      }
      const challenge = challengeSnap.data() as DeviceChallengeDoc;
      const now = Timestamp.now();
      if (challenge.deviceId !== deviceId) {
        throw new HttpsError("permission-denied", "This challenge was not issued for this device.");
      }
      if (challenge.consumedAt !== null) {
        throw new HttpsError("failed-precondition", "This challenge has already been consumed.");
      }
      if (challenge.expiresAt.toMillis() < now.toMillis()) {
        throw new HttpsError("failed-precondition", "This challenge has expired.");
      }
      if (!verifySignature(device.signatureAlgorithm, device.publicKeyPem, challenge.nonce, signature)) {
        throw new HttpsError("permission-denied", "Signature verification failed.");
      }

      // Single-use — consumed inside this same transaction, replay-safe.
      tx.update(challengeRef, { consumedAt: now });

      const sessionRef = db.collection("deviceSessions").doc();
      const session: DeviceSessionDoc = {
        deviceId,
        organizationId,
        branchId,
        status: "active",
        issuedAt: now,
        expiresAt: Timestamp.fromMillis(now.toMillis() + SESSION_DURATION_SECONDS * 1000),
        lastStaffUid: request.auth!.uid,
      };
      tx.set(sessionRef, session);
      tx.update(deviceRef, { lastSeenAt: now });

      writeAuditEvent({
        tx,
        db,
        eventId: `${deviceId}-session-issued-${sessionRef.id}`,
        organizationId,
        branchId,
        type: "device.sessionIssued",
        targetRef: deviceRef.path,
        actorType: "device",
        actorUid: request.auth!.uid,
        correlationId,
        clientRequestId,
        now,
      });

      return { sessionId: sessionRef.id, expiresAt: session.expiresAt.toDate().toISOString() };
    });

    return { ...result, deviceId, correlationId };
  },
);

/**
 * Server-side-only verification a device-restricted callable can import —
 * NEVER exposed as a client Firestore read (Correction #5). Fails closed
 * on a missing, expired, or revoked session, or one issued for a
 * different device/branch than claimed.
 */
export async function requireActiveDeviceSession(
  organizationId: string,
  branchId: string,
  deviceId: string,
  sessionId: string,
): Promise<void> {
  const db = getFirestore();
  const snap = await db.collection("deviceSessions").doc(sessionId).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "No such device session.");
  }
  const session = snap.data() as DeviceSessionDoc;
  if (session.deviceId !== deviceId || session.organizationId !== organizationId || session.branchId !== branchId) {
    throw new HttpsError("permission-denied", "Device session does not match the requested device/branch.");
  }
  if (session.status !== "active") {
    throw new HttpsError("permission-denied", "Device session is not active.");
  }
  if (session.expiresAt.toMillis() < Date.now()) {
    throw new HttpsError("permission-denied", "Device session has expired.");
  }
}

/** Manager+ (`manageDevices`) — immediate, unconditional revocation. Idempotent (no-op if already revoked/retired). */
export const revokeTrustedDevice = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const branchId = requireNonEmptyString(data.branchId, "branchId");
    const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
    const reason = requireNonEmptyString(data.reason, "reason");

    requireStaffPermission(request, organizationId, "manageDevices");
    requireBranchAccess(request, organizationId, branchId);

    const db = getFirestore();
    const { ref, data: device } = await loadDeviceRegistration(db, organizationId, branchId, deviceId);
    if (device.status === "revoked" || device.status === "retired") {
      return { deviceId, revoked: false, alreadyRevoked: true };
    }

    const correlationId = generateCorrelationId();
    const now = Timestamp.now();

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current = snap.data() as DeviceRegistrationDoc;
      tx.update(ref, {
        status: "revoked" as DeviceStatus,
        revokedAt: now,
        revokedReason: reason,
        version: current.version + 1,
      });

      // Every outstanding session for this device is revoked in the same
      // transaction — a revoked device can never keep operating on an
      // already-issued session (Correction #5: "Session revoke/expire
      // durumları anında hassas komutlarda kontrol edilsin").
      const sessionsSnap = await db
        .collection("deviceSessions")
        .where("deviceId", "==", deviceId)
        .where("status", "==", "active")
        .get();
      for (const sessionDoc of sessionsSnap.docs) {
        tx.update(sessionDoc.ref, { status: "revoked" });
      }

      writeAuditEvent({
        tx,
        db,
        eventId: `${deviceId}-revoked-v${current.version + 1}`,
        organizationId,
        branchId,
        type: "device.revoked",
        targetRef: ref.path,
        previousValue: current.status,
        newValue: "revoked",
        actorType: "staff",
        actorUid: request.auth!.uid,
        reasonMessage: reason,
        correlationId,
        now,
      });
    });

    return { deviceId, revoked: true, alreadyRevoked: false, correlationId };
  },
);
