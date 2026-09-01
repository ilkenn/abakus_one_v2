import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { PAYMENT_SESSIONS_COLLECTION, REFUND_REQUESTS_COLLECTION, type PaymentSessionDoc, type RefundRequestDoc } from "./paymentDomain";
import { CASH_SESSIONS_COLLECTION, type CashSessionDoc } from "./cashDomain";
import { FISCAL_OPERATION_JOURNAL_COLLECTION, OFFLINE_LEASES_COLLECTION, type FiscalOperationJournalEntry, type OfflineLease } from "./fiscalDomain";

/**
 * AP-4 Wave D — the real, branch-wide read boundary Admin's financial
 * destinations consume. Distinct from `paymentOperationalView.ts`/
 * `cashOperationalView.ts` (per-check/per-session lookups the POS checkout/
 * cash screens poll) — these list a whole branch's recent records for
 * Admin's own review/reconciliation surfaces. No Firestore `.snapshots()`
 * listener — a bounded, permission-gated callable, same reasoning as
 * `listReservationsForBranch.ts`'s own established Admin-list pattern
 * (no trusted-device requirement — Admin panel access is a separate
 * surface from the POS device-binding model).
 *
 * Deliberately simple pagination this wave (a flat `limit`, no cursor) —
 * a real, working "recent N records" view, not a placeholder; full
 * cursor-based pagination is additive, not a breaking change, if a branch's
 * real volume ever needs it.
 */

const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 200;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}
function resolvePageSize(raw: unknown): number {
  return Math.min(MAX_PAGE_SIZE, Math.max(1, typeof raw === "number" && Number.isInteger(raw) ? raw : DEFAULT_PAGE_SIZE));
}
function requireAdminView(request: CallableRequest, organizationId: string, branchId: string): void {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  requireStaffPermission(request, organizationId, "processPayments");
  requireBranchAccess(request, organizationId, branchId);
}

export const listPaymentSessionsForBranch = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  requireAdminView(request, organizationId, branchId);
  const pageSize = resolvePageSize(data.pageSize);

  const db = getFirestore();
  const snap = await db.collection(PAYMENT_SESSIONS_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("branchId", "==", branchId)
    .orderBy("createdAt", "desc")
    .limit(pageSize)
    .get();

  return {
    sessions: snap.docs.map((doc) => {
      const s = doc.data() as PaymentSessionDoc;
      return {
        sessionId: doc.id, checkId: s.checkId, status: s.status,
        payableAmountMinorUnits: s.payableAmountMinorUnits, settledAmountMinorUnits: s.settledAmountMinorUnits,
        currencyCode: s.currencyCode, createdAt: s.createdAt.toDate().toISOString(),
      };
    }),
  };
});

export const listRefundsForBranch = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  requireAdminView(request, organizationId, branchId);
  const pageSize = resolvePageSize(data.pageSize);

  const db = getFirestore();
  const snap = await db.collection(REFUND_REQUESTS_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("branchId", "==", branchId)
    .orderBy("createdAt", "desc")
    .limit(pageSize)
    .get();

  return {
    refunds: snap.docs.map((doc) => {
      const r = doc.data() as RefundRequestDoc;
      return {
        refundId: doc.id, checkId: r.checkId, refundType: r.refundType, amountMinorUnits: r.amountMinorUnits,
        status: r.status, reasonCode: r.reasonCode, createdAt: r.createdAt.toDate().toISOString(),
      };
    }),
  };
});

export const listCashSessionsForBranch = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  requireAdminView(request, organizationId, branchId);
  const pageSize = resolvePageSize(data.pageSize);

  const db = getFirestore();
  const snap = await db.collection(CASH_SESSIONS_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("branchId", "==", branchId)
    .orderBy("createdAt", "desc")
    .limit(pageSize)
    .get();

  return {
    sessions: snap.docs.map((doc) => {
      const s = doc.data() as CashSessionDoc;
      return {
        sessionId: doc.id, drawerId: s.drawerId, status: s.status, businessDate: s.businessDate,
        openingFloatAmountMinorUnits: s.openingFloatAmountMinorUnits, settledAmountMinorUnits: s.settledAmountMinorUnits,
        currencyCode: s.currencyCode, createdAt: s.createdAt.toDate().toISOString(),
      };
    }),
  };
});

export const listFiscalOperationsForBranch = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  requireAdminView(request, organizationId, branchId);
  const pageSize = resolvePageSize(data.pageSize);
  // Reconciliation-queue view: only entries genuinely needing human review.
  // `timedOut` is included alongside the two explicit "needs reconciliation"
  // statuses — no sweep exists yet (AP-4 Wave D) that promotes a `timedOut`
  // fiscal entry to `unknownReconciliationRequired` (`fiscalDomain.ts`'s
  // transition map declares it valid, but nothing in this codebase performs
  // it), so a real timed-out device round-trip must still surface here today
  // rather than sitting invisible to Admin until that sweep is built.
  const onlyUnresolved = data.onlyUnresolved === true;

  const db = getFirestore();
  let query = db.collection(FISCAL_OPERATION_JOURNAL_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("branchId", "==", branchId);
  if (onlyUnresolved) {
    query = query.where("status", "in", ["timedOut", "unknownReconciliationRequired", "manualInterventionRequired"]);
  }
  const snap = await query.orderBy("createdAt", "desc").limit(pageSize).get();

  return {
    entries: snap.docs.map((doc) => {
      const e = doc.data() as FiscalOperationJournalEntry;
      return {
        entryId: doc.id, operationType: e.operationType, status: e.status,
        amountMinorUnits: e.amountMinorUnits, currencyCode: e.currencyCode,
        checkId: e.checkId, providerId: e.providerId, createdAt: e.createdAt.toDate().toISOString(),
        resolvedAt: e.resolvedAt ? e.resolvedAt.toDate().toISOString() : null,
      };
    }),
  };
});

export const listOfflineLeasesForBranch = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  requireAdminView(request, organizationId, branchId);
  const pageSize = resolvePageSize(data.pageSize);

  const db = getFirestore();
  const snap = await db.collection(OFFLINE_LEASES_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("branchId", "==", branchId)
    .orderBy("createdAt", "desc")
    .limit(pageSize)
    .get();

  return {
    leases: snap.docs.map((doc) => {
      const l = doc.data() as OfflineLease;
      return {
        leaseId: doc.id, deviceId: l.deviceId, issuedToStaffUid: l.issuedToStaffUid,
        expiresAt: l.expiresAt.toDate().toISOString(), revoked: l.revoked,
        transactionsUsed: l.transactionsUsed, maxTransactionCount: l.maxTransactionCount,
        createdAt: l.createdAt.toDate().toISOString(),
      };
    }),
  };
});
