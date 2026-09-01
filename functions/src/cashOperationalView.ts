import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import {
  CASH_DRAWERS_COLLECTION,
  CASH_SESSIONS_COLLECTION,
  CASH_MOVEMENTS_COLLECTION,
  CASH_COUNTS_COLLECTION,
  CASH_RECONCILIATIONS_COLLECTION,
  cashSessionCountsAsOpen,
  type CashDrawerDoc,
  type CashSessionDoc,
  type CashMovementDoc,
  type CashCountDoc,
  type CashReconciliationDoc,
} from "./cashDomain";

/**
 * AP-4 Wave D — the real, staff/POS read boundary onto `cashDrawers`/
 * `cashSessions`/`cashMovements`/`cashCounts`/`cashReconciliations` (all
 * five total Firestore lockdowns). Mirrors `paymentOperationalView.ts`'s
 * own reasoning exactly — this is the "purpose-built operational-view
 * callable" every Wave B doc comment disclosed as deferred to this wave.
 */

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}

/** Lists every registered drawer for the branch, plus which (if any) currently has an open/awaiting-approval session. */
export const listCashDrawers = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");

  requireStaffPermission(request, organizationId, "manageCashSessions");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

  const db = getFirestore();
  const drawersSnap = await db.collection(CASH_DRAWERS_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("branchId", "==", branchId)
    .get();
  const sessionsSnap = await db.collection(CASH_SESSIONS_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("branchId", "==", branchId)
    .get();
  const openSessionByDrawer = new Map<string, { sessionId: string; status: string }>();
  for (const doc of sessionsSnap.docs) {
    const session = doc.data() as CashSessionDoc;
    if (cashSessionCountsAsOpen(session.status)) {
      openSessionByDrawer.set(session.drawerId, { sessionId: doc.id, status: session.status });
    }
  }

  return {
    drawers: drawersSnap.docs.map((doc) => {
      const drawer = doc.data() as CashDrawerDoc;
      const openSession = openSessionByDrawer.get(doc.id) ?? null;
      return { drawerId: doc.id, name: drawer.name, isActive: drawer.isActive, openSession };
    }),
  };
});

/** The full operational snapshot for one cash session — movements, counts, reconciliations. */
export const getCashSessionOperationalView = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const sessionId = requireNonEmptyString(data.sessionId, "sessionId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");

  requireStaffPermission(request, organizationId, "manageCashSessions");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

  const db = getFirestore();
  const sessionSnap = await db.collection(CASH_SESSIONS_COLLECTION).doc(sessionId).get();
  if (!sessionSnap.exists) return { exists: false as const };
  const session = sessionSnap.data() as CashSessionDoc;
  if (session.organizationId !== organizationId || session.branchId !== branchId) {
    throw new HttpsError("not-found", "Cash session not found.");
  }

  const movementsSnap = await db.collection(CASH_MOVEMENTS_COLLECTION).where("sessionId", "==", sessionId).get();
  const countsSnap = await db.collection(CASH_COUNTS_COLLECTION).where("sessionId", "==", sessionId).get();
  const reconciliationsSnap = await db.collection(CASH_RECONCILIATIONS_COLLECTION).where("sessionId", "==", sessionId).get();

  return {
    exists: true as const,
    sessionId,
    drawerId: session.drawerId,
    status: session.status,
    businessDate: session.businessDate,
    openingFloatAmountMinorUnits: session.openingFloatAmountMinorUnits,
    settledAmountMinorUnits: session.settledAmountMinorUnits,
    currencyCode: session.currencyCode,
    cashRegisterModel: session.cashRegisterModel,
    openedByStaffUid: session.openedByStaffUid,
    closedByStaffUid: session.closedByStaffUid,
    movements: movementsSnap.docs
      .map((doc) => doc.data() as CashMovementDoc)
      .sort((a, b) => a.timestamp.toMillis() - b.timestamp.toMillis())
      .map((m) => ({
        type: m.type,
        amountMinorUnits: m.amountMinorUnits,
        reason: m.reason,
        actorStaffUid: m.actorStaffUid,
        timestamp: m.timestamp.toDate().toISOString(),
      })),
    counts: countsSnap.docs
      .map((doc) => ({ id: doc.id, data: doc.data() as CashCountDoc }))
      .sort((a, b) => a.data.declaredAt.toMillis() - b.data.declaredAt.toMillis())
      .map(({ id, data: c }) => ({
        countId: id,
        expectedAmountMinorUnits: c.expectedAmountMinorUnits,
        actualAmountMinorUnits: c.actualAmountMinorUnits,
        variance: c.variance,
        declaredAt: c.declaredAt.toDate().toISOString(),
      })),
    reconciliations: reconciliationsSnap.docs
      .map((doc) => doc.data() as CashReconciliationDoc)
      .sort((a, b) => a.reviewedAt.toMillis() - b.reviewedAt.toMillis())
      .map((r) => ({
        status: r.status,
        varianceAccepted: r.varianceAccepted,
        variance: r.variance,
        reviewedByStaffUid: r.reviewedByStaffUid,
        reviewedAt: r.reviewedAt.toDate().toISOString(),
      })),
  };
});
