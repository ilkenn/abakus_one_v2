import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { SINGLE_TENANT_ORGANIZATION_ID, TENANT_CUSTOMERS_COLLECTION } from "./completeCustomerProfile";
import { LOYALTY_LEDGER_ENTRIES_COLLECTION, LEDGER_ENTRY_TYPES, type LedgerEntryType } from "./loyaltyLedger";

/**
 * `getCustomerLoyaltyHistory` — Boncuk Loyalty Program P3A (2026-08-23).
 *
 * A narrow, trusted, customer-safe READ over `loyaltyLedgerEntries` — the
 * one path the customer-facing Boncuklarım screen's movement history uses.
 * Mirrors `getCustomerLoyaltySnapshot.ts`'s exact identity/tenant discipline
 * (real phone customer only, `organizationId` resolved exclusively
 * server-side, tenant membership independently re-verified) and
 * `listReservationsForBranch.ts`'s exact bounded single-field cursor
 * pagination shape (`pageSize` clamped, `cursor` an ISO timestamp string of
 * the last-walked sort field, `startAfter` on that one field).
 *
 * **Why a callable, not a direct client Firestore query — even though
 * `firestore.rules`' existing owner+tenant read rule already makes a
 * correctly-scoped client query access-safe.** Firestore rules control
 * *access* to a document, not *which fields* of it a query result exposes —
 * a raw client query would still return the entry's full internal
 * accounting provenance (`entitlementDeltaBoncuk`/`spendableDeltaBoncuk`/
 * `debtDeltaBoncuk`, `orderEligibleNetSpendBefore/AfterMinorUnits`,
 * `orderEntitlementBefore/AfterBoncuk`, `debtBefore/AfterBoncuk`,
 * `earningRateMinorUnitsPerBoncuk`, `idempotencyKey`, `reversalOf`) over
 * the wire to a customer's device — internal ledger reconciliation state
 * with zero customer-facing meaning. This callable returns a minimal,
 * sanitized row shape instead ([CustomerLoyaltyHistoryRow]) — the
 * customer-safe seam this feature is built against, not a security
 * workaround for an otherwise-unsafe read.
 *
 * **Customer-safe delta mapping.** A single ledger entry's economic effect
 * is inherently split across three first-class fields
 * (`BR-LOYALTY-016`) — this callable collapses that into ONE display
 * number per row, chosen by entry-type direction:
 * - **Earning/reversal-direction** types (`orderEarn`, `orderEarnReversal`,
 *   `wheelEarn`, `wheelExpiry`, `taskEarn`, `taskReversal`,
 *   `adminAdjustment`) — `displayBoncukDelta = entitlementDeltaBoncuk` (the
 *   gross event size, e.g. "5 Boncuk kazandın" even if all 5 went to debt),
 *   and `debtAppliedBoncuk = entitlementDeltaBoncuk - spendableDeltaBoncuk`
 *   (how much of that gross amount was redirected to debt repayment rather
 *   than becoming spendable — always `0` when no debt existed).
 * - **Redemption/restoration-direction** types (`boncukRedemption`,
 *   `boncukRedemptionRestore`, `catalogRedemption`,
 *   `catalogRedemptionRestore`) — `displayBoncukDelta = spendableDeltaBoncuk`
 *   directly (`entitlementDeltaBoncuk` is always `0` for these by design —
 *   BR-LOYALTY-016 — spending/restoring already-earned Boncuk never changes
 *   how much was earned), and `debtAppliedBoncuk = 0` always (redemption
 *   never interacts with debt).
 *
 * Turkish display copy is deliberately NOT generated here — `type` is
 * returned as the closed, English, machine-stable enum value, and the
 * Flutter client owns the Turkish label mapping (`lib/features/loyalty/`),
 * consistent with keeping localization a client concern.
 *
 * **Only `orderEarn` can appear in a real result today** — no writer for
 * any other entry type exists yet (P2b reversal, redemption, catalog,
 * wheel, tasks are all future phases). The mapping above is written to be
 * correct for all 11 closed entry types so the client's Turkish-label
 * switch never needs to change shape when those phases ship — but this
 * callable never fabricates a row for an entry type nothing writes yet.
 */

const DEFAULT_PAGE_SIZE = 15;
const MAX_PAGE_SIZE = 30;

export interface CustomerLoyaltyHistoryRow {
  eventId: string;
  type: LedgerEntryType;
  displayBoncukDelta: number;
  debtAppliedBoncuk: number;
  occurredAt: string;
  orderId: string | null;
}

export interface CustomerLoyaltyHistoryPage {
  rows: CustomerLoyaltyHistoryRow[];
  nextCursor: string | null;
}

const EARNING_OR_REVERSAL_DIRECTION_TYPES: readonly LedgerEntryType[] = [
  "orderEarn",
  "orderEarnReversal",
  "wheelEarn",
  "wheelExpiry",
  "taskEarn",
  "taskReversal",
  "adminAdjustment",
];

function isEarningOrReversalDirection(type: LedgerEntryType): boolean {
  return (EARNING_OR_REVERSAL_DIRECTION_TYPES as readonly string[]).includes(type);
}

function toIso(value: unknown): string | null {
  const asDate = (value as { toDate?: () => Date } | undefined)?.toDate?.();
  return asDate instanceof Date ? asDate.toISOString() : null;
}

/** Exported for direct unit testing without a Firestore document wrapper. */
export function mapLedgerEntryToCustomerHistoryRow(
  entryId: string,
  data: FirebaseFirestore.DocumentData,
): CustomerLoyaltyHistoryRow | null {
  const type = data.entryType as LedgerEntryType | undefined;
  if (!type || !(LEDGER_ENTRY_TYPES as readonly string[]).includes(type)) return null;

  const entitlementDeltaBoncuk = typeof data.entitlementDeltaBoncuk === "number" ? data.entitlementDeltaBoncuk : 0;
  const spendableDeltaBoncuk = typeof data.spendableDeltaBoncuk === "number" ? data.spendableDeltaBoncuk : 0;

  const earningDirection = isEarningOrReversalDirection(type);
  const displayBoncukDelta = earningDirection ? entitlementDeltaBoncuk : spendableDeltaBoncuk;
  const debtAppliedBoncuk = earningDirection ? entitlementDeltaBoncuk - spendableDeltaBoncuk : 0;

  const occurredAt = toIso(data.createdAt);
  if (!occurredAt) return null;

  return {
    eventId: entryId,
    type,
    displayBoncukDelta,
    debtAppliedBoncuk,
    occurredAt,
    orderId: typeof data.orderId === "string" ? data.orderId : null,
  };
}

export const getCustomerLoyaltyHistory = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest): Promise<CustomerLoyaltyHistoryPage> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Loyalty requires a real, phone-verified customer identity.",
      );
    }
    const uid = request.auth.uid;

    // Never client-supplied — identical discipline to getCustomerLoyaltySnapshot.ts.
    const organizationId = SINGLE_TENANT_ORGANIZATION_ID;

    const db = getFirestore();
    const membershipSnap = await db
      .collection(TENANT_CUSTOMERS_COLLECTION)
      .doc(`${organizationId}_${uid}`)
      .get();
    if (!membershipSnap.exists) {
      throw new HttpsError("permission-denied", "You are not a customer of this organization.");
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    const pageSize = Math.min(
      MAX_PAGE_SIZE,
      Math.max(1, typeof data.pageSize === "number" && Number.isFinite(data.pageSize) ? Math.floor(data.pageSize) : DEFAULT_PAGE_SIZE),
    );

    let cursorTimestamp: Timestamp | null = null;
    if (data.cursor !== undefined && data.cursor !== null) {
      if (typeof data.cursor !== "string") {
        throw new HttpsError("invalid-argument", "cursor must be an ISO 8601 timestamp string.");
      }
      const parsed = new Date(data.cursor);
      if (Number.isNaN(parsed.getTime())) {
        throw new HttpsError("invalid-argument", "cursor must be a valid ISO 8601 timestamp.");
      }
      cursorTimestamp = Timestamp.fromDate(parsed);
    }

    let query = db
      .collection(LOYALTY_LEDGER_ENTRIES_COLLECTION)
      .where("organizationId", "==", organizationId)
      .where("customerId", "==", uid)
      .orderBy("createdAt", "desc")
      .limit(pageSize);
    if (cursorTimestamp) {
      query = query.startAfter(cursorTimestamp);
    }

    const snapshot = await query.get();

    const rows: CustomerLoyaltyHistoryRow[] = [];
    for (const doc of snapshot.docs) {
      const row = mapLedgerEntryToCustomerHistoryRow(doc.id, doc.data());
      if (row) rows.push(row);
    }

    const nextCursor =
      snapshot.docs.length === pageSize ? toIso(snapshot.docs[snapshot.docs.length - 1].data().createdAt) : null;

    return { rows, nextCursor };
  },
);
