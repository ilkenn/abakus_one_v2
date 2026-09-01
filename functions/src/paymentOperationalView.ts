import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { PAYMENT_INTENTS_COLLECTION, PAYMENT_SESSIONS_COLLECTION, PAYMENT_ATTEMPTS_COLLECTION, REFUND_REQUESTS_COLLECTION, type PaymentIntentDoc, type PaymentSessionDoc, type PaymentAttemptDoc, type RefundRequestDoc } from "./paymentDomain";

/**
 * AP-4 Wave D — the sole staff/POS read path onto `paymentIntents`/
 * `paymentSessions`/`paymentAttempts`/`refundRequests` (all four are total
 * Firestore lockdowns, `allow read: if false`, same reasoning
 * `posOperationalView.ts`'s own doc comment already established: Firestore
 * Rules cannot verify AP-2's trusted-device proof). This is the "purpose-
 * built operational-view callable" every AP-4 Wave A/B/C doc comment
 * disclosed as deferred to this exact wave — the checkout UI's canonical
 * source for payable/settled/remaining amounts and every attempt's real
 * status. The client NEVER derives "remaining" from its own locally-
 * tracked tender history; it always re-reads this view after every action.
 *
 * Read-only, same polling/pull-to-refresh trade-off as
 * `getPosTableOperationalView`. Reuses `processPayments` (already
 * staff-tier) rather than inventing a new read-only permission — viewing
 * payment state is a strict prerequisite of every payment mutation that
 * permission already gates.
 *
 * Sanitized projection only: never `providerRef`/`providerResponseSummary`
 * verbatim beyond what a cashier's own screen needs to show (no raw PAN/
 * OTP/secret ever existed in these fields to begin with — see
 * `PaymentAttemptDoc`'s own doc comment — but this callable still narrows
 * the shape deliberately rather than returning documents verbatim).
 */

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}

export const getPaymentSessionOperationalView = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const branchId = requireNonEmptyString(data.branchId, "branchId");
    const checkId = requireNonEmptyString(data.checkId, "checkId");
    const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
    const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");

    requireStaffPermission(request, organizationId, "processPayments");
    requireBranchAccess(request, organizationId, branchId);
    await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

    const db = getFirestore();
    const sessionId = `session-${checkId}`;
    const sessionSnap = await db.collection(PAYMENT_SESSIONS_COLLECTION).doc(sessionId).get();
    if (!sessionSnap.exists) {
      return { exists: false as const };
    }
    const session = sessionSnap.data() as PaymentSessionDoc;
    if (session.organizationId !== organizationId || session.branchId !== branchId) {
      throw new HttpsError("not-found", "Payment session not found.");
    }

    const intentSnap = await db.collection(PAYMENT_INTENTS_COLLECTION).doc(session.intentId).get();
    const intent = intentSnap.exists ? (intentSnap.data() as PaymentIntentDoc) : null;

    const attemptsSnap = await db.collection(PAYMENT_ATTEMPTS_COLLECTION).where("sessionId", "==", sessionId).get();
    const attempts = attemptsSnap.docs.map((doc) => {
      const a = doc.data() as PaymentAttemptDoc;
      return {
        attemptId: doc.id,
        tenderType: a.tenderType,
        status: a.status,
        amountMinorUnits: a.amountMinorUnits,
        allocations: a.allocations,
        declineReason: a.declineReason,
        idempotencyKey: a.idempotencyKey,
        createdAt: a.createdAt.toDate().toISOString(),
        resolvedAt: a.resolvedAt ? a.resolvedAt.toDate().toISOString() : null,
      };
    });

    const refundsSnap = await db.collection(REFUND_REQUESTS_COLLECTION).where("checkId", "==", checkId).get();
    const refunds = refundsSnap.docs.map((doc) => {
      const r = doc.data() as RefundRequestDoc;
      return {
        refundId: doc.id,
        refundType: r.refundType,
        amountMinorUnits: r.amountMinorUnits,
        status: r.status,
        allocations: r.allocations,
        reasonCode: r.reasonCode,
        approvalRequestRef: r.approvalRequestRef,
        createdAt: r.createdAt.toDate().toISOString(),
        resolvedAt: r.resolvedAt ? r.resolvedAt.toDate().toISOString() : null,
      };
    });

    return {
      exists: true as const,
      sessionId,
      sessionStatus: session.status,
      payableAmountMinorUnits: session.payableAmountMinorUnits,
      settledAmountMinorUnits: session.settledAmountMinorUnits,
      currencyCode: session.currencyCode,
      intent: intent
        ? {
            intentId: session.intentId,
            subAccountAllocations: intent.subAccountAllocations,
            serviceCharges: intent.serviceCharges,
          }
        : null,
      attempts,
      refunds,
    };
  },
);
