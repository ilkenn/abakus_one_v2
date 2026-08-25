import { Timestamp, type Firestore, type Transaction } from "firebase-admin/firestore";

/**
 * `campaignUsage` — Server-Authoritative Campaign Engine P8-B (2026-08-25).
 *
 * Race-safe, transactional usage-reservation primitives for a campaign's
 * global `usageLimit` and `perCustomerUsageLimit` — the deterministic-id +
 * transactional-read-before-write pattern already proven by
 * `loyaltyLedgerEntries`' own idempotency discipline
 * (`deriveLoyaltyLedgerEntryId` + `tx.get()`/`tx.create()` inside one
 * transaction), never a bare `FieldValue.increment()` fired without a
 * preceding read-gate (which cannot enforce a ceiling and would
 * oversubscribe under concurrency — the exact failure mode this file exists
 * to prevent).
 *
 * **Composable, not self-managing** — [reserveCampaignUsage] and
 * [releaseCampaignUsage] both accept an existing `tx: Transaction` and
 * perform no `db.runTransaction()` of their own, deliberately mirroring
 * `loyaltyPolicy.ts`'s own "transaction-scoped read/write pair, composed
 * into a larger transaction" shape (referenced by
 * `loyaltyRewardCatalogAdminService.ts`'s own doc comment as the precedent
 * for "when should an operation manage its own transaction vs. accept
 * one"). A campaign usage reservation is only ever correct when it is
 * ATOMIC WITH the order creation that consumes it (locked P8-A/P8-B
 * requirement) — accepting the caller's `tx` is what makes that possible.
 *
 * **Not yet called from any order-submission or lifecycle path (P8-B is
 * foundation only).** [reserveCampaignUsage] is designed to be called
 * from inside a future `submit*Order.ts` transaction, alongside order
 * creation; [releaseCampaignUsage] is designed to be called from a future
 * release-consumer mirroring `loyaltyRedemptionRestore.ts`'s own
 * `onDocumentCreated("orderEvents/{eventId}")` trigger shape, when a
 * reserved order later reaches `rejected`/`cancelled`/`refunded`. Neither
 * is wired into any such path this phase.
 *
 * **Three collections**:
 * - `campaignUsageCounters/{organizationId}_{campaignId}` — the campaign's
 *   own running global usage count.
 * - `campaignCustomerUsage/{organizationId}_{campaignId}_{customerId}` —
 *   one specific customer's running usage count against this campaign.
 *   Never created for an anonymous guest (`customerId: null` — see this
 *   file's own [ReserveCampaignUsageParams] doc comment on why).
 * - `campaignUsageReservations/{organizationId}_{campaignId}_{orderId}` —
 *   the deterministic per-order reservation record. Its own existence is
 *   the authoritative idempotency check for BOTH reserve (a retried
 *   submission with the same `orderId` is a safe no-op, never a second
 *   count) and release (a retried release event is a safe no-op, never a
 *   second decrement) — mirrors `loyaltyRedemptionRestore.ts`'s own
 *   "the deterministic id, not a boolean flag alone, is the authoritative
 *   idempotency check" discipline.
 */

export const CAMPAIGN_USAGE_COUNTERS_COLLECTION = "campaignUsageCounters";
export const CAMPAIGN_CUSTOMER_USAGE_COLLECTION = "campaignCustomerUsage";
export const CAMPAIGN_USAGE_RESERVATIONS_COLLECTION = "campaignUsageReservations";

function usageCounterDocId(organizationId: string, campaignId: string): string {
  return `${organizationId}_${campaignId}`;
}

function customerUsageDocId(organizationId: string, campaignId: string, customerId: string): string {
  return `${organizationId}_${campaignId}_${customerId}`;
}

function reservationDocId(organizationId: string, campaignId: string, orderId: string): string {
  return `${organizationId}_${campaignId}_${orderId}`;
}

/**
 * **`customerId: null` means an anonymous table guest** (locked P8-A/P8-B
 * decision: "GuestAuthUid is NOT a durable per-customer identity" — a fresh
 * `guestAuthUid` is minted per table session, so it can never anchor a
 * meaningful cross-visit "per customer" count). When `customerId` is
 * `null`, no `campaignCustomerUsage` document is ever read or written —
 * `perCustomerUsageLimit` is therefore only ever enforceable for a real,
 * phone-verified customer identity. A caller wiring this into checkout
 * must independently enforce the locked rule "anonymous guests may use a
 * campaign ONLY when `perCustomerUsageLimit == null`" BEFORE ever calling
 * this function with `customerId: null` — this function itself does not
 * re-derive that policy; it only reserves what it's asked to reserve.
 */
export interface ReserveCampaignUsageParams {
  organizationId: string;
  campaignId: string;
  customerId: string | null;
  orderId: string;
  usageLimit: number | null;
  perCustomerUsageLimit: number | null;
}

export type ReserveCampaignUsageResult =
  | { status: "reserved" }
  | { status: "already-reserved" }
  | { status: "global-limit-reached" }
  | { status: "customer-limit-reached" };

export async function reserveCampaignUsage(
  db: Firestore,
  tx: Transaction,
  params: ReserveCampaignUsageParams,
  now: Timestamp = Timestamp.now(),
): Promise<ReserveCampaignUsageResult> {
  const { organizationId, campaignId, customerId, orderId, usageLimit, perCustomerUsageLimit } = params;

  const reservationRef = db
    .collection(CAMPAIGN_USAGE_RESERVATIONS_COLLECTION)
    .doc(reservationDocId(organizationId, campaignId, orderId));
  const counterRef = db
    .collection(CAMPAIGN_USAGE_COUNTERS_COLLECTION)
    .doc(usageCounterDocId(organizationId, campaignId));
  const customerCounterRef =
    customerId !== null
      ? db.collection(CAMPAIGN_CUSTOMER_USAGE_COLLECTION).doc(customerUsageDocId(organizationId, campaignId, customerId))
      : null;

  // Reads first, always — every tx.get() this reservation will ever
  // perform happens before any write, mirroring every other transactional
  // primitive in this codebase.
  const reservationSnap = await tx.get(reservationRef);
  if (reservationSnap.exists) {
    // A retried submission with the same idempotency key — the caller's
    // own order-level dedupe already guarantees this is the SAME logical
    // request, never a second real usage.
    return { status: "already-reserved" };
  }

  const counterSnap = await tx.get(counterRef);
  const currentGlobalCount = counterSnap.exists ? ((counterSnap.data()!.usageCount as number) ?? 0) : 0;
  if (usageLimit !== null && currentGlobalCount >= usageLimit) {
    return { status: "global-limit-reached" };
  }

  let currentCustomerCount = 0;
  if (customerCounterRef !== null) {
    const customerCounterSnap = await tx.get(customerCounterRef);
    currentCustomerCount = customerCounterSnap.exists ? ((customerCounterSnap.data()!.usageCount as number) ?? 0) : 0;
    if (perCustomerUsageLimit !== null && currentCustomerCount >= perCustomerUsageLimit) {
      return { status: "customer-limit-reached" };
    }
  }

  // Write phase — every tx.get() above has already happened.
  tx.set(
    counterRef,
    { organizationId, campaignId, usageCount: currentGlobalCount + 1, updatedAt: now },
    { merge: true },
  );
  if (customerCounterRef !== null && customerId !== null) {
    tx.set(
      customerCounterRef,
      { organizationId, campaignId, customerId, usageCount: currentCustomerCount + 1, updatedAt: now },
      { merge: true },
    );
  }
  // tx.create — not tx.set — so Firestore's own atomic "fail if exists"
  // backs up the tx.get() existence check above with a second layer,
  // exactly mirroring the loyalty ledger's own defense-in-depth idiom.
  tx.create(reservationRef, {
    organizationId,
    campaignId,
    customerId,
    orderId,
    status: "reserved",
    reservedAt: now,
    releasedAt: null,
  });

  return { status: "reserved" };
}

export interface ReleaseCampaignUsageParams {
  organizationId: string;
  campaignId: string;
  orderId: string;
}

export type ReleaseCampaignUsageResult =
  | { status: "released" }
  | { status: "already-released" }
  | { status: "no-reservation-found" };

/**
 * Idempotent — a duplicate release event (retried trigger delivery, or the
 * same terminal order-status update somehow producing two outbox records)
 * can never double-decrement a counter, mirroring
 * `loyaltyRedemptionRestore.ts`'s own idempotency discipline exactly.
 */
export async function releaseCampaignUsage(
  db: Firestore,
  tx: Transaction,
  params: ReleaseCampaignUsageParams,
  now: Timestamp = Timestamp.now(),
): Promise<ReleaseCampaignUsageResult> {
  const { organizationId, campaignId, orderId } = params;
  const reservationRef = db
    .collection(CAMPAIGN_USAGE_RESERVATIONS_COLLECTION)
    .doc(reservationDocId(organizationId, campaignId, orderId));

  const reservationSnap = await tx.get(reservationRef);
  if (!reservationSnap.exists) {
    // Nothing was ever reserved for this (organizationId, campaignId,
    // orderId) — a clean, deterministic no-op (e.g. the order never used
    // this campaign at all).
    return { status: "no-reservation-found" };
  }
  const reservation = reservationSnap.data()!;
  if (reservation.status === "released") {
    return { status: "already-released" };
  }

  const customerId = (reservation.customerId as string | null) ?? null;
  const counterRef = db
    .collection(CAMPAIGN_USAGE_COUNTERS_COLLECTION)
    .doc(usageCounterDocId(organizationId, campaignId));
  const customerCounterRef =
    customerId !== null
      ? db.collection(CAMPAIGN_CUSTOMER_USAGE_COLLECTION).doc(customerUsageDocId(organizationId, campaignId, customerId))
      : null;

  const counterSnap = await tx.get(counterRef);
  const currentGlobalCount = counterSnap.exists ? ((counterSnap.data()!.usageCount as number) ?? 0) : 0;

  let currentCustomerCount = 0;
  if (customerCounterRef !== null) {
    const customerCounterSnap = await tx.get(customerCounterRef);
    currentCustomerCount = customerCounterSnap.exists ? ((customerCounterSnap.data()!.usageCount as number) ?? 0) : 0;
  }

  // Write phase.
  tx.set(counterRef, { usageCount: Math.max(0, currentGlobalCount - 1), updatedAt: now }, { merge: true });
  if (customerCounterRef !== null) {
    tx.set(customerCounterRef, { usageCount: Math.max(0, currentCustomerCount - 1), updatedAt: now }, { merge: true });
  }
  tx.set(reservationRef, { status: "released", releasedAt: now }, { merge: true });

  return { status: "released" };
}
