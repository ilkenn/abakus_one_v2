import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess, roleHasPermission } from "./staffAuthorization";
import type { StaffPermission } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import { createApprovalRequest } from "./remoteApproval";
import type { ActionHandlerParams, ActionHandlerResult } from "./remoteApproval";
import { BRANCH_PAYMENT_CONFIG_COLLECTION, PAYMENT_ATTEMPTS_COLLECTION, type BranchPaymentConfigDoc, type PaymentAttemptDoc } from "./paymentDomain";
import {
  CASH_DRAWERS_COLLECTION,
  CASH_SESSIONS_COLLECTION,
  CASH_MOVEMENTS_COLLECTION,
  CASH_COUNTS_COLLECTION,
  CASH_RECONCILIATIONS_COLLECTION,
  CASH_ADJUSTMENTS_COLLECTION,
  CASH_MOVEMENT_REQUESTS_COLLECTION,
  CASH_ADJUSTMENT_REQUESTS_COLLECTION,
  computeBusinessDate,
  computeCashVariance,
  cashMovementIsInflow,
  cashSessionCountsAsOpen,
  sanitizeRequestableCashMovementType,
  type CashDrawerDoc,
  type CashSessionDoc,
  type CashMovementDoc,
  type CashCountDoc,
  type CashReconciliationDoc,
  type CashAdjustmentDoc,
} from "./cashDomain";

/**
 * AP-4 Wave B — the real, server-authoritative cash register engine.
 * Ports the Flutter prototype's business rules (BR-CASH-001 through
 * BR-CASH-009, `docs/business_rules.md`) into Cloud Functions, adding the
 * governing instruction's own extensions: manager-authorized opening
 * (on-site or remote), mandatory-approval non-sale movements, and
 * server-computed/branch-timezone-authoritative business dates. See
 * `cashDomain.ts`'s own doc comment for the full framing.
 */

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}
function requirePositiveInt(raw: unknown, field: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0) invalid(`${field} must be a positive integer.`);
  return raw as number;
}
function requireNonNegativeInt(raw: unknown, field: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 0) invalid(`${field} must be a non-negative integer.`);
  return raw as number;
}
function sanitizeNotes(raw: unknown): string {
  if (typeof raw !== "string") return "";
  const trimmed = raw.trim();
  return trimmed.length > 1000 ? trimmed.slice(0, 1000) : trimmed;
}

interface StaffDeviceContext {
  organizationId: string;
  branchId: string;
  uid: string;
}

async function authorizeCashCommand(request: CallableRequest, data: Record<string, unknown>): Promise<StaffDeviceContext> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  requireStaffPermission(request, organizationId, "manageCashSessions");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);
  return { organizationId, branchId, uid: request.auth.uid };
}

/** Boolean mirror of `requireStaffPermission` — never throws, used to decide the "manager may self-authorize on-site" branch without aborting the request for a base-tier staff member. */
function actorHasPermission(request: CallableRequest, organizationId: string, permission: StaffPermission): boolean {
  const token = request.auth?.token;
  const organizationAccess = token?.organizationAccess;
  if (!Array.isArray(organizationAccess) || !organizationAccess.includes(organizationId)) return false;
  const rolesByOrg = token?.roles as Record<string, unknown> | undefined;
  const rolesForOrg = rolesByOrg?.[organizationId];
  return Array.isArray(rolesForOrg) && rolesForOrg.some((role) => typeof role === "string" && roleHasPermission(role, permission));
}

/** Branch policy this wave introduces: a `cashierBound` drawer may only be operated by the staff uid that opened it. Not enforced for `sharedDrawer` (any branch-scoped staff with `manageCashSessions`). */
function requireSessionOperableByActor(session: CashSessionDoc, uid: string): void {
  if (session.cashRegisterModel === "cashierBound" && session.openedByStaffUid !== uid) {
    throw new HttpsError("permission-denied", "This drawer is cashier-bound to the staff member who opened it.");
  }
}

async function resolveBranchCashPolicy(
  db: Firestore,
  tx: FirebaseFirestore.Transaction,
  branchId: string,
): Promise<{ timezone: string; cutoverHour: number; cashRegisterModel: "sharedDrawer" | "cashierBound" }> {
  const configSnap = await tx.get(db.collection(BRANCH_PAYMENT_CONFIG_COLLECTION).doc(branchId));
  const config = configSnap.exists ? (configSnap.data() as BranchPaymentConfigDoc) : null;
  return {
    timezone: config?.timezone ?? "Europe/Istanbul",
    cutoverHour: config?.businessDayCutoverHour ?? 0,
    cashRegisterModel: config?.cashRegisterModel ?? "sharedDrawer",
  };
}

// -----------------------------------------------------------------------
// createCashDrawer — manager-tier registry setup
// -----------------------------------------------------------------------

export const createCashDrawer = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  const name = requireNonEmptyString(data.name, "name");
  requireStaffPermission(request, organizationId, "approveCashReconciliation");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

  const db = getFirestore();
  const now = Timestamp.now();
  const ref = db.collection(CASH_DRAWERS_COLLECTION).doc();
  const doc: CashDrawerDoc = {
    organizationId, branchId, name, isActive: true,
    createdAt: now, createdByStaffUid: request.auth.uid, updatedAt: now, version: 1,
  };
  await ref.set(doc);
  return { drawerId: ref.id };
});

// -----------------------------------------------------------------------
// requestCashSessionOpen — manager-authorized (on-site self-open, or
// remote approval for a base-tier staff member)
// -----------------------------------------------------------------------

export const requestCashSessionOpen = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { organizationId, branchId, uid } = await authorizeCashCommand(request, data);
  const drawerId = requireNonEmptyString(data.drawerId, "drawerId");
  const openingFloatAmountMinorUnits = requireNonNegativeInt(data.openingFloatAmountMinorUnits, "openingFloatAmountMinorUnits");
  const currencyCode = requireNonEmptyString(data.currencyCode, "currencyCode");
  const reason = requireNonEmptyString(data.reason, "reason");

  const db = getFirestore();
  const sessionId = db.collection(CASH_SESSIONS_COLLECTION).doc().id;
  const isManager = actorHasPermission(request, organizationId, "approveCashReconciliation");

  const result = await db.runTransaction(async (tx) => {
    const drawerRef = db.collection(CASH_DRAWERS_COLLECTION).doc(drawerId);
    const drawerSnap = await tx.get(drawerRef);
    if (!drawerSnap.exists) throw new HttpsError("not-found", "Cash drawer not found.");
    const drawer = drawerSnap.data() as CashDrawerDoc;
    if (drawer.organizationId !== organizationId || drawer.branchId !== branchId) {
      throw new HttpsError("not-found", "Cash drawer not found.");
    }
    if (!drawer.isActive) throw new HttpsError("failed-precondition", "This cash drawer is not in service.");

    // BR-CASH-002 — only one open (non-closed, non-openRejected) session per drawer.
    const existingSessionsSnap = await tx.get(db.collection(CASH_SESSIONS_COLLECTION).where("drawerId", "==", drawerId));
    const alreadyOpen = existingSessionsSnap.docs.some((d) => cashSessionCountsAsOpen((d.data() as CashSessionDoc).status));
    if (alreadyOpen) {
      throw new HttpsError("failed-precondition", "This drawer already has an open cash session.", { code: "cashRegister/drawer-already-open" });
    }

    const policy = await resolveBranchCashPolicy(db, tx, branchId);
    const now = Timestamp.now();
    const businessDate = computeBusinessDate(now.toMillis(), policy.timezone, policy.cutoverHour);
    const sessionRef = db.collection(CASH_SESSIONS_COLLECTION).doc(sessionId);

    if (isManager) {
      const session: CashSessionDoc = {
        organizationId, branchId, drawerId, status: "active", businessDate,
        openingFloatAmountMinorUnits, currencyCode,
        requestedByStaffUid: uid, openedByStaffUid: uid, openedAt: now,
        cashRegisterModel: policy.cashRegisterModel, settledAmountMinorUnits: openingFloatAmountMinorUnits,
        closedByStaffUid: null, closedAt: null, finalCashCountId: null, finalReconciliationId: null,
        createdAt: now, updatedAt: now, version: 1,
      };
      tx.set(sessionRef, session);
      const movement: CashMovementDoc = {
        organizationId, branchId, sessionId, drawerId, type: "openingFloat",
        amountMinorUnits: openingFloatAmountMinorUnits, currencyCode, reason,
        actorStaffUid: uid, timestamp: now, reversalOfMovementId: null, paymentAttemptId: null, refundRequestId: null,
      };
      tx.set(db.collection(CASH_MOVEMENTS_COLLECTION).doc(), movement);
      writeAuditEvent({
        tx, db, eventId: `${sessionId}-opened`, organizationId, branchId,
        type: "cashSession.opened", targetRef: sessionRef.path,
        newValue: { drawerId, openingFloatAmountMinorUnits, businessDate },
        actorType: "staff", actorUid: uid,
        correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
      });
      return { sessionId, status: "active" as const, needsApproval: false as const };
    }

    const session: CashSessionDoc = {
      organizationId, branchId, drawerId, status: "awaitingOpenApproval", businessDate,
      openingFloatAmountMinorUnits, currencyCode,
      requestedByStaffUid: uid, openedByStaffUid: null, openedAt: null,
      cashRegisterModel: policy.cashRegisterModel, settledAmountMinorUnits: 0,
      closedByStaffUid: null, closedAt: null, finalCashCountId: null, finalReconciliationId: null,
      createdAt: now, updatedAt: now, version: 1,
    };
    tx.set(sessionRef, session);
    writeAuditEvent({
      tx, db, eventId: `${sessionId}-open-requested`, organizationId, branchId,
      type: "cashSession.openRequested", targetRef: sessionRef.path,
      newValue: { drawerId, openingFloatAmountMinorUnits, businessDate },
      actorType: "staff", actorUid: uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });
    return { sessionId, status: "awaitingOpenApproval" as const, needsApproval: true as const };
  });

  if (!result.needsApproval) return { sessionId: result.sessionId, status: result.status };

  const approval = await createApprovalRequest({
    organizationId, branchId, actionType: "cashSessionOpen", requestedByActorUid: uid,
    targetAggregateRef: db.collection(CASH_SESSIONS_COLLECTION).doc(sessionId).path,
    targetAggregateVersion: 1,
    payloadHash: `${drawerId}-${openingFloatAmountMinorUnits}`,
  });
  return { sessionId: result.sessionId, status: result.status, approvalRequestId: approval.requestId };
});

/** The allowlisted `cashSessionOpen` approve handler. */
export async function applyCashSessionOpen(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now } = params;
  const ref = db.doc(approval.targetAggregateRef);
  const snap = await tx.get(ref);
  if (!snap.exists) throw new HttpsError("not-found", "The cash session no longer exists.");
  const session = snap.data() as CashSessionDoc;
  if (session.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The cash session has changed since this approval was created.");
  }
  if (session.status !== "awaitingOpenApproval") {
    throw new HttpsError("failed-precondition", `Cash session is already "${session.status}".`);
  }

  tx.update(ref, {
    status: "active", openedByStaffUid: session.requestedByStaffUid, openedAt: now,
    settledAmountMinorUnits: session.openingFloatAmountMinorUnits, updatedAt: now, version: session.version + 1,
  });
  const movement: CashMovementDoc = {
    organizationId: session.organizationId, branchId: session.branchId, sessionId: ref.id, drawerId: session.drawerId,
    type: "openingFloat", amountMinorUnits: session.openingFloatAmountMinorUnits, currencyCode: session.currencyCode,
    reason: "Cash session opened (remote-approved).", actorStaffUid: session.requestedByStaffUid,
    timestamp: now, reversalOfMovementId: null, paymentAttemptId: null, refundRequestId: null,
  };
  tx.set(db.collection(CASH_MOVEMENTS_COLLECTION).doc(), movement);
  return { newValue: { status: "active" } };
}

/** The allowlisted `cashSessionOpen` reject handler. */
export async function applyCashSessionOpenRejected(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now } = params;
  const ref = db.doc(approval.targetAggregateRef);
  const snap = await tx.get(ref);
  if (!snap.exists) throw new HttpsError("not-found", "The cash session no longer exists.");
  const session = snap.data() as CashSessionDoc;
  if (session.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The cash session has changed since this approval was created.");
  }
  if (session.status !== "awaitingOpenApproval") {
    throw new HttpsError("failed-precondition", `Cash session is already "${session.status}".`);
  }
  tx.update(ref, { status: "openRejected", updatedAt: now, version: session.version + 1 });
  return { newValue: { status: "openRejected" } };
}

// -----------------------------------------------------------------------
// requestCashMovement — non-sale in/out, ALWAYS manager-approved (no
// on-site self-authorization shortcut, unlike session open)
// -----------------------------------------------------------------------

export const requestCashMovement = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { organizationId, branchId, uid } = await authorizeCashCommand(request, data);
  const sessionId = requireNonEmptyString(data.sessionId, "sessionId");
  const movementType = sanitizeRequestableCashMovementType(data.movementType);
  const magnitudeMinorUnits = requirePositiveInt(data.amountMinorUnits, "amountMinorUnits");
  const reason = requireNonEmptyString(data.reason, "reason");

  const db = getFirestore();
  const requestId = db.collection(CASH_MOVEMENT_REQUESTS_COLLECTION).doc().id;

  await db.runTransaction(async (tx) => {
    const sessionRef = db.collection(CASH_SESSIONS_COLLECTION).doc(sessionId);
    const sessionSnap = await tx.get(sessionRef);
    if (!sessionSnap.exists) throw new HttpsError("not-found", "Cash session not found.");
    const session = sessionSnap.data() as CashSessionDoc;
    if (session.organizationId !== organizationId || session.branchId !== branchId) {
      throw new HttpsError("not-found", "Cash session not found.");
    }
    if (session.status !== "active") {
      throw new HttpsError("failed-precondition", `Cash session must be "active" to record a movement (current: "${session.status}").`);
    }
    requireSessionOperableByActor(session, uid);

    const isInflow = cashMovementIsInflow(movementType);
    const signedAmountMinorUnits = isInflow ? magnitudeMinorUnits : -magnitudeMinorUnits;
    const now = Timestamp.now();
    const reqRef = db.collection(CASH_MOVEMENT_REQUESTS_COLLECTION).doc(requestId);
    tx.set(reqRef, {
      organizationId, branchId, sessionId, drawerId: session.drawerId,
      movementType, amountMinorUnits: signedAmountMinorUnits, currencyCode: session.currencyCode,
      reason, requestedByStaffUid: uid, status: "pendingApproval",
      createdAt: now, resolvedAt: null, resultingMovementId: null, approvalRequestRef: null, version: 1,
    });
    writeAuditEvent({
      tx, db, eventId: `${requestId}-requested`, organizationId, branchId,
      type: "cashMovement.requested", targetRef: reqRef.path,
      newValue: { sessionId, movementType, amountMinorUnits: signedAmountMinorUnits },
      actorType: "staff", actorUid: uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });
  });

  const approval = await createApprovalRequest({
    organizationId, branchId, actionType: "cashMovement", requestedByActorUid: uid,
    targetAggregateRef: db.collection(CASH_MOVEMENT_REQUESTS_COLLECTION).doc(requestId).path,
    targetAggregateVersion: 1,
    payloadHash: `${sessionId}-${movementType}-${magnitudeMinorUnits}`,
  });
  await db.collection(CASH_MOVEMENT_REQUESTS_COLLECTION).doc(requestId).update({ approvalRequestRef: approval.requestId });
  return { requestId, status: "pendingApproval" as const, approvalRequestId: approval.requestId };
});

interface CashMovementRequestDoc {
  organizationId: string;
  branchId: string;
  sessionId: string;
  drawerId: string;
  movementType: string;
  amountMinorUnits: number;
  currencyCode: string;
  reason: string;
  requestedByStaffUid: string;
  status: "pendingApproval" | "applied" | "rejected";
  createdAt: Timestamp;
  resolvedAt: Timestamp | null;
  resultingMovementId: string | null;
  approvalRequestRef: string | null;
  version: number;
}

/** The allowlisted `cashMovement` approve handler. */
export async function applyCashMovement(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now } = params;
  const reqRef = db.doc(approval.targetAggregateRef);
  const reqSnap = await tx.get(reqRef);
  if (!reqSnap.exists) throw new HttpsError("not-found", "The cash movement request no longer exists.");
  const reqDoc = reqSnap.data() as CashMovementRequestDoc;
  if (reqDoc.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The cash movement request has changed since this approval was created.");
  }
  if (reqDoc.status !== "pendingApproval") {
    throw new HttpsError("failed-precondition", `This cash movement request is already "${reqDoc.status}".`);
  }

  const sessionRef = db.collection(CASH_SESSIONS_COLLECTION).doc(reqDoc.sessionId);
  const sessionSnap = await tx.get(sessionRef);
  if (!sessionSnap.exists) throw new HttpsError("not-found", "The cash session no longer exists.");
  const session = sessionSnap.data() as CashSessionDoc;
  if (session.status !== "active") {
    throw new HttpsError("failed-precondition", `Cash session is no longer "active" (current: "${session.status}") — cannot apply this movement.`);
  }

  const movementRef = db.collection(CASH_MOVEMENTS_COLLECTION).doc();
  const movement: CashMovementDoc = {
    organizationId: reqDoc.organizationId, branchId: reqDoc.branchId, sessionId: reqDoc.sessionId, drawerId: reqDoc.drawerId,
    type: reqDoc.movementType as CashMovementDoc["type"], amountMinorUnits: reqDoc.amountMinorUnits, currencyCode: reqDoc.currencyCode,
    reason: reqDoc.reason, actorStaffUid: reqDoc.requestedByStaffUid,
    timestamp: now, reversalOfMovementId: null, paymentAttemptId: null, refundRequestId: null,
  };
  tx.set(movementRef, movement);
  tx.update(reqRef, { status: "applied", resolvedAt: now, resultingMovementId: movementRef.id, version: reqDoc.version + 1 });
  tx.update(sessionRef, { settledAmountMinorUnits: session.settledAmountMinorUnits + reqDoc.amountMinorUnits, updatedAt: now, version: session.version + 1 });
  return { newValue: { status: "applied", movementId: movementRef.id } };
}

/** The allowlisted `cashMovement` reject handler. */
export async function applyCashMovementRejected(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now } = params;
  const reqRef = db.doc(approval.targetAggregateRef);
  const reqSnap = await tx.get(reqRef);
  if (!reqSnap.exists) throw new HttpsError("not-found", "The cash movement request no longer exists.");
  const reqDoc = reqSnap.data() as CashMovementRequestDoc;
  if (reqDoc.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The cash movement request has changed since this approval was created.");
  }
  if (reqDoc.status !== "pendingApproval") {
    throw new HttpsError("failed-precondition", `This cash movement request is already "${reqDoc.status}".`);
  }
  tx.update(reqRef, { status: "rejected", resolvedAt: now, version: reqDoc.version + 1 });
  return { newValue: { status: "rejected" } };
}

// -----------------------------------------------------------------------
// requestCashAdjustment — manager-approved correction (BR-CASH-009)
// -----------------------------------------------------------------------

export const requestCashAdjustment = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { organizationId, branchId, uid } = await authorizeCashCommand(request, data);
  const sessionId = requireNonEmptyString(data.sessionId, "sessionId");
  const rawAmount = data.amountMinorUnits;
  if (typeof rawAmount !== "number" || !Number.isInteger(rawAmount) || rawAmount === 0) {
    invalid("amountMinorUnits must be a non-zero integer (correction sign is caller-supplied).");
  }
  const amountMinorUnits = rawAmount as number;
  const reason = requireNonEmptyString(data.reason, "reason");

  const db = getFirestore();
  const requestId = db.collection(CASH_ADJUSTMENT_REQUESTS_COLLECTION).doc().id;

  await db.runTransaction(async (tx) => {
    const sessionRef = db.collection(CASH_SESSIONS_COLLECTION).doc(sessionId);
    const sessionSnap = await tx.get(sessionRef);
    if (!sessionSnap.exists) throw new HttpsError("not-found", "Cash session not found.");
    const session = sessionSnap.data() as CashSessionDoc;
    if (session.organizationId !== organizationId || session.branchId !== branchId) {
      throw new HttpsError("not-found", "Cash session not found.");
    }
    if (session.status !== "active") {
      throw new HttpsError("failed-precondition", `Cash session must be "active" to record an adjustment (current: "${session.status}").`);
    }
    requireSessionOperableByActor(session, uid);

    const now = Timestamp.now();
    const reqRef = db.collection(CASH_ADJUSTMENT_REQUESTS_COLLECTION).doc(requestId);
    tx.set(reqRef, {
      organizationId, branchId, sessionId, drawerId: session.drawerId,
      amountMinorUnits, currencyCode: session.currencyCode, reason,
      requestedByStaffUid: uid, status: "pendingApproval",
      createdAt: now, resolvedAt: null, resultingAdjustmentId: null, approvalRequestRef: null, version: 1,
    });
    writeAuditEvent({
      tx, db, eventId: `${requestId}-requested`, organizationId, branchId,
      type: "cashAdjustment.requested", targetRef: reqRef.path,
      newValue: { sessionId, amountMinorUnits },
      actorType: "staff", actorUid: uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });
  });

  const approval = await createApprovalRequest({
    organizationId, branchId, actionType: "cashAdjustment", requestedByActorUid: uid,
    targetAggregateRef: db.collection(CASH_ADJUSTMENT_REQUESTS_COLLECTION).doc(requestId).path,
    targetAggregateVersion: 1,
    payloadHash: `${sessionId}-${amountMinorUnits}`,
  });
  await db.collection(CASH_ADJUSTMENT_REQUESTS_COLLECTION).doc(requestId).update({ approvalRequestRef: approval.requestId });
  return { requestId, status: "pendingApproval" as const, approvalRequestId: approval.requestId };
});

interface CashAdjustmentRequestDoc {
  organizationId: string;
  branchId: string;
  sessionId: string;
  drawerId: string;
  amountMinorUnits: number;
  currencyCode: string;
  reason: string;
  requestedByStaffUid: string;
  status: "pendingApproval" | "applied" | "rejected";
  createdAt: Timestamp;
  resolvedAt: Timestamp | null;
  resultingAdjustmentId: string | null;
  approvalRequestRef: string | null;
  version: number;
}

/** The allowlisted `cashAdjustment` approve handler. BR-CASH-007's self-approval ban is already enforced generically by `respondToApprovalRequest` (the requester can never respond to their own request) — `approvedByStaffUid` below is therefore structurally guaranteed to differ from `requestedByStaffUid`. */
export async function applyCashAdjustment(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now, respondedByActorUid } = params;
  const reqRef = db.doc(approval.targetAggregateRef);
  const reqSnap = await tx.get(reqRef);
  if (!reqSnap.exists) throw new HttpsError("not-found", "The cash adjustment request no longer exists.");
  const reqDoc = reqSnap.data() as CashAdjustmentRequestDoc;
  if (reqDoc.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The cash adjustment request has changed since this approval was created.");
  }
  if (reqDoc.status !== "pendingApproval") {
    throw new HttpsError("failed-precondition", `This cash adjustment request is already "${reqDoc.status}".`);
  }

  const sessionRef = db.collection(CASH_SESSIONS_COLLECTION).doc(reqDoc.sessionId);
  const sessionSnap = await tx.get(sessionRef);
  if (!sessionSnap.exists) throw new HttpsError("not-found", "The cash session no longer exists.");
  const session = sessionSnap.data() as CashSessionDoc;
  if (session.status !== "active") {
    throw new HttpsError("failed-precondition", `Cash session is no longer "active" (current: "${session.status}") — cannot apply this adjustment.`);
  }

  const movementRef = db.collection(CASH_MOVEMENTS_COLLECTION).doc();
  const movement: CashMovementDoc = {
    organizationId: reqDoc.organizationId, branchId: reqDoc.branchId, sessionId: reqDoc.sessionId, drawerId: reqDoc.drawerId,
    type: "correction", amountMinorUnits: reqDoc.amountMinorUnits, currencyCode: reqDoc.currencyCode,
    reason: reqDoc.reason, actorStaffUid: reqDoc.requestedByStaffUid,
    timestamp: now, reversalOfMovementId: null, paymentAttemptId: null, refundRequestId: null,
  };
  tx.set(movementRef, movement);

  const adjustmentRef = db.collection(CASH_ADJUSTMENTS_COLLECTION).doc();
  const adjustment: CashAdjustmentDoc = {
    organizationId: reqDoc.organizationId, branchId: reqDoc.branchId, sessionId: reqDoc.sessionId,
    movementId: movementRef.id, reason: reqDoc.reason,
    requestedByStaffUid: reqDoc.requestedByStaffUid, approvedByStaffUid: respondedByActorUid, createdAt: now,
  };
  tx.set(adjustmentRef, adjustment);

  tx.update(reqRef, { status: "applied", resolvedAt: now, resultingAdjustmentId: adjustmentRef.id, version: reqDoc.version + 1 });
  tx.update(sessionRef, { settledAmountMinorUnits: session.settledAmountMinorUnits + reqDoc.amountMinorUnits, updatedAt: now, version: session.version + 1 });
  return { newValue: { status: "applied", adjustmentId: adjustmentRef.id, movementId: movementRef.id } };
}

/** The allowlisted `cashAdjustment` reject handler. */
export async function applyCashAdjustmentRejected(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now } = params;
  const reqRef = db.doc(approval.targetAggregateRef);
  const reqSnap = await tx.get(reqRef);
  if (!reqSnap.exists) throw new HttpsError("not-found", "The cash adjustment request no longer exists.");
  const reqDoc = reqSnap.data() as CashAdjustmentRequestDoc;
  if (reqDoc.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The cash adjustment request has changed since this approval was created.");
  }
  if (reqDoc.status !== "pendingApproval") {
    throw new HttpsError("failed-precondition", `This cash adjustment request is already "${reqDoc.status}".`);
  }
  tx.update(reqRef, { status: "rejected", resolvedAt: now, version: reqDoc.version + 1 });
  return { newValue: { status: "rejected" } };
}

// -----------------------------------------------------------------------
// submitCashCount — server-frozen expected amount (BR-CASH-004), triggers
// the mandatory manager reconciliation approval (BR-CASH-006)
// -----------------------------------------------------------------------

export const submitCashCount = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { organizationId, branchId, uid } = await authorizeCashCommand(request, data);
  const sessionId = requireNonEmptyString(data.sessionId, "sessionId");
  const actualAmountMinorUnits = requireNonNegativeInt(data.actualAmountMinorUnits, "actualAmountMinorUnits");
  const notes = sanitizeNotes(data.notes);

  const db = getFirestore();
  const countId = db.collection(CASH_COUNTS_COLLECTION).doc().id;

  const result = await db.runTransaction(async (tx) => {
    const sessionRef = db.collection(CASH_SESSIONS_COLLECTION).doc(sessionId);
    const sessionSnap = await tx.get(sessionRef);
    if (!sessionSnap.exists) throw new HttpsError("not-found", "Cash session not found.");
    const session = sessionSnap.data() as CashSessionDoc;
    if (session.organizationId !== organizationId || session.branchId !== branchId) {
      throw new HttpsError("not-found", "Cash session not found.");
    }
    // BR-CASH-005 — a rejected session recounts directly into pendingApproval, no separate reactivate step.
    if (session.status !== "active" && session.status !== "rejected") {
      throw new HttpsError("failed-precondition", `Cash session must be "active" or "rejected" to submit a count (current: "${session.status}").`);
    }
    requireSessionOperableByActor(session, uid);

    // BR-CASH-004 — expected amount computed once here, frozen, from every movement recorded so far.
    const movementsSnap = await tx.get(db.collection(CASH_MOVEMENTS_COLLECTION).where("sessionId", "==", sessionId));
    const expectedAmountMinorUnits = movementsSnap.docs.reduce((sum, d) => sum + (d.data() as CashMovementDoc).amountMinorUnits, 0);

    const now = Timestamp.now();
    const variance = computeCashVariance(expectedAmountMinorUnits, actualAmountMinorUnits);
    const countRef = db.collection(CASH_COUNTS_COLLECTION).doc(countId);
    const count: CashCountDoc = {
      organizationId, branchId, sessionId, expectedAmountMinorUnits, actualAmountMinorUnits, notes, variance,
      declaredByStaffUid: uid, declaredAt: now,
    };
    tx.set(countRef, count);

    const nextVersion = session.version + 1;
    tx.update(sessionRef, { status: "pendingApproval", updatedAt: now, version: nextVersion });
    writeAuditEvent({
      tx, db, eventId: `${countId}-submitted`, organizationId, branchId,
      type: "cashCount.submitted", targetRef: countRef.path,
      newValue: { sessionId, expectedAmountMinorUnits, actualAmountMinorUnits, variance },
      actorType: "staff", actorUid: uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });
    return { countId, expectedAmountMinorUnits, variance, sessionVersionAfter: nextVersion };
  });

  const approval = await createApprovalRequest({
    organizationId, branchId, actionType: "cashReconciliation", requestedByActorUid: uid,
    targetAggregateRef: db.collection(CASH_SESSIONS_COLLECTION).doc(sessionId).path,
    targetAggregateVersion: result.sessionVersionAfter,
    payloadHash: `${sessionId}-${result.countId}`,
  });
  return {
    countId: result.countId, expectedAmountMinorUnits: result.expectedAmountMinorUnits,
    variance: result.variance, status: "pendingApproval" as const, approvalRequestId: approval.requestId,
  };
});

/** The allowlisted `cashReconciliation` approve handler — approving IS accepting whatever variance (if any) the count showed; a manager who does not accept it responds "rejected" instead (BR-CASH-008). */
export async function applyCashReconciliationApproved(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now, respondedByActorUid } = params;
  const sessionRef = db.doc(approval.targetAggregateRef);
  const sessionSnap = await tx.get(sessionRef);
  if (!sessionSnap.exists) throw new HttpsError("not-found", "The cash session no longer exists.");
  const session = sessionSnap.data() as CashSessionDoc;
  if (session.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The cash session has changed since this approval was created.");
  }
  if (session.status !== "pendingApproval") {
    throw new HttpsError("failed-precondition", `Cash session is already "${session.status}".`);
  }

  const countsSnap = await tx.get(
    db.collection(CASH_COUNTS_COLLECTION).where("sessionId", "==", sessionRef.id).orderBy("declaredAt", "desc").limit(1),
  );
  if (countsSnap.empty) throw new HttpsError("internal", "No cash count found for this session.");
  const countDoc = countsSnap.docs[0];
  const count = countDoc.data() as CashCountDoc;

  const reconciliationRef = db.collection(CASH_RECONCILIATIONS_COLLECTION).doc();
  const reconciliation: CashReconciliationDoc = {
    organizationId: session.organizationId, branchId: session.branchId, sessionId: sessionRef.id,
    cashCountId: countDoc.id, status: "approved", reviewedByStaffUid: respondedByActorUid, reviewedAt: now,
    managerComments: "", varianceAccepted: true, variance: count.variance,
  };
  tx.set(reconciliationRef, reconciliation);

  let settledAmountMinorUnits = session.settledAmountMinorUnits;
  if (count.variance.type !== "exact") {
    const signedDiff = count.variance.type === "over" ? count.variance.amountMinorUnits : -count.variance.amountMinorUnits;
    const movement: CashMovementDoc = {
      organizationId: session.organizationId, branchId: session.branchId, sessionId: sessionRef.id, drawerId: session.drawerId,
      type: "closingDifference", amountMinorUnits: signedDiff, currencyCode: session.currencyCode,
      reason: `Cash count variance accepted (${count.variance.type}, ${count.variance.amountMinorUnits} minor units).`,
      actorStaffUid: respondedByActorUid, timestamp: now, reversalOfMovementId: null, paymentAttemptId: null, refundRequestId: null,
    };
    tx.set(db.collection(CASH_MOVEMENTS_COLLECTION).doc(), movement);
    settledAmountMinorUnits += signedDiff;
  }

  tx.update(sessionRef, {
    status: "approved", settledAmountMinorUnits, finalCashCountId: countDoc.id, finalReconciliationId: reconciliationRef.id,
    updatedAt: now, version: session.version + 1,
  });
  return { newValue: { status: "approved", reconciliationId: reconciliationRef.id } };
}

/** The allowlisted `cashReconciliation` reject handler — BR-CASH-005: the session returns to a recountable state, never a dead end. */
export async function applyCashReconciliationRejected(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now, respondedByActorUid } = params;
  const sessionRef = db.doc(approval.targetAggregateRef);
  const sessionSnap = await tx.get(sessionRef);
  if (!sessionSnap.exists) throw new HttpsError("not-found", "The cash session no longer exists.");
  const session = sessionSnap.data() as CashSessionDoc;
  if (session.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The cash session has changed since this approval was created.");
  }
  if (session.status !== "pendingApproval") {
    throw new HttpsError("failed-precondition", `Cash session is already "${session.status}".`);
  }

  const countsSnap = await tx.get(
    db.collection(CASH_COUNTS_COLLECTION).where("sessionId", "==", sessionRef.id).orderBy("declaredAt", "desc").limit(1),
  );
  if (countsSnap.empty) throw new HttpsError("internal", "No cash count found for this session.");
  const countDoc = countsSnap.docs[0];
  const count = countDoc.data() as CashCountDoc;

  const reconciliationRef = db.collection(CASH_RECONCILIATIONS_COLLECTION).doc();
  const reconciliation: CashReconciliationDoc = {
    organizationId: session.organizationId, branchId: session.branchId, sessionId: sessionRef.id,
    cashCountId: countDoc.id, status: "rejected", reviewedByStaffUid: respondedByActorUid, reviewedAt: now,
    managerComments: "", varianceAccepted: false, variance: count.variance,
  };
  tx.set(reconciliationRef, reconciliation);

  tx.update(sessionRef, { status: "rejected", updatedAt: now, version: session.version + 1 });
  return { newValue: { status: "rejected", reconciliationId: reconciliationRef.id } };
}

// -----------------------------------------------------------------------
// closeCashSession — only from "approved" (BR-CASH-006)
// -----------------------------------------------------------------------

export const closeCashSession = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { organizationId, branchId, uid } = await authorizeCashCommand(request, data);
  const sessionId = requireNonEmptyString(data.sessionId, "sessionId");

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const sessionRef = db.collection(CASH_SESSIONS_COLLECTION).doc(sessionId);
    const sessionSnap = await tx.get(sessionRef);
    if (!sessionSnap.exists) throw new HttpsError("not-found", "Cash session not found.");
    const session = sessionSnap.data() as CashSessionDoc;
    if (session.organizationId !== organizationId || session.branchId !== branchId) {
      throw new HttpsError("not-found", "Cash session not found.");
    }
    if (session.status !== "approved") {
      throw new HttpsError("failed-precondition", `Cash session must be "approved" to close (current: "${session.status}").`);
    }
    requireSessionOperableByActor(session, uid);

    // Gün sonu kilidi — herhangi bir masa hâlâ açıksa kasa kapanışı reddedilir
    // (BR-CASH-011). `restaurantTables` bu branch için sınırlı sayıda belge
    // taşır (aynı sayfalama disiplemi `getPosBranchTableOverview` içinde de
    // kullanılıyor) — sınırsız bir tarama değil.
    const branchTablesSnap = await tx.get(db.collection("restaurantTables").where("branchId", "==", branchId));
    const openTables = branchTablesSnap.docs.filter((d) => (d.data().activeTableSessionId ?? null) !== null);
    if (openTables.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        `${openTables.length} masa hâlâ açık — gün sonu kapanışından önce tüm masalar kapatılmalı.`,
        {
          code: "openTables",
          tableIds: openTables.map((d) => d.id),
          tableDisplayNames: openTables.map((d) => (d.data().displayName as string | undefined) ?? d.id),
        },
      );
    }

    const now = Timestamp.now();
    tx.update(sessionRef, { status: "closed", closedByStaffUid: uid, closedAt: now, updatedAt: now, version: session.version + 1 });
    writeAuditEvent({
      tx, db, eventId: `${sessionId}-closed`, organizationId, branchId,
      type: "cashSession.closed", targetRef: sessionRef.path,
      newValue: { businessDate: session.businessDate },
      actorType: "staff", actorUid: uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });
    return { sessionId, status: "closed" as const };
  });
});

// -----------------------------------------------------------------------
// getDailyRevenueSummary — Gün Sonu (BR-CASH-011) revenue-by-tender-type
// read, feeding the End of Day screen's Nakit/Kredi Kartı/Diğer summary.
// -----------------------------------------------------------------------

/** A branch realistically settles nowhere near this many payment attempts
 * within one drawer session — a generous, disclosed bound, not a silent
 * truncation risk (mirrors `getPosBranchTableOverview`'s own bounded-read
 * discipline elsewhere in this codebase). */
const DAILY_REVENUE_ATTEMPT_LIMIT = 5000;

export const getDailyRevenueSummary = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeCashCommand(request, data);
  const sessionId = requireNonEmptyString(data.sessionId, "sessionId");

  const db = getFirestore();
  const sessionSnap = await db.collection(CASH_SESSIONS_COLLECTION).doc(sessionId).get();
  if (!sessionSnap.exists) throw new HttpsError("not-found", "Cash session not found.");
  const session = sessionSnap.data() as CashSessionDoc;
  if (session.organizationId !== ctx.organizationId || session.branchId !== ctx.branchId) {
    throw new HttpsError("not-found", "Cash session not found.");
  }
  if (!session.openedAt) {
    throw new HttpsError("failed-precondition", "This cash session has not opened yet.");
  }

  // Reused verbatim from `paymentDomain.ts`'s own `isAttemptSettled` set
  // (`"succeeded" | "resolvedSucceeded"`) — a Firestore query needs literal
  // values, so the two are spelled out here rather than calling the
  // function, but they are exactly what it defines as settled money.
  const attemptsSnap = await db.collection(PAYMENT_ATTEMPTS_COLLECTION)
    .where("branchId", "==", ctx.branchId)
    .where("status", "in", ["succeeded", "resolvedSucceeded"])
    .where("createdAt", ">=", session.openedAt)
    .limit(DAILY_REVENUE_ATTEMPT_LIMIT)
    .get();

  let cashMinorUnits = 0;
  let cardMinorUnits = 0;
  let otherMinorUnits = 0;
  for (const doc of attemptsSnap.docs) {
    const attempt = doc.data() as PaymentAttemptDoc;
    if (attempt.currencyCode !== session.currencyCode) continue; // single-currency summary, disclosed simplification
    switch (attempt.tenderType) {
      case "cash":
        cashMinorUnits += attempt.amountMinorUnits;
        break;
      case "card":
        cardMinorUnits += attempt.amountMinorUnits;
        break;
      case "mealCard":
      case "boncuk":
        otherMinorUnits += attempt.amountMinorUnits;
        break;
    }
  }

  return {
    sessionId,
    currencyCode: session.currencyCode,
    cashMinorUnits,
    cardMinorUnits,
    otherMinorUnits,
    totalMinorUnits: cashMinorUnits + cardMinorUnits + otherMinorUnits,
  };
});
