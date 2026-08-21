import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import type { Firestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { TENANT_CUSTOMERS_COLLECTION } from "./completeCustomerProfile";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK,
  deriveLoyaltyLedgerEntryId,
  type LoyaltyLedgerEntry,
} from "./loyaltyLedger";
import type { LoyaltyAccountData } from "./getCustomerLoyaltySnapshot";
import { hasServerPricingAuthority } from "./orderPricingAuthority";

/**
 * `loyaltyOrderEarning` — Boncuk Loyalty Program P2A (2026-08-20).
 *
 * Consumes the existing `orderEvents/{orderId}-completed` transactional
 * outbox record (`onOrderCompleted.ts`, Sprint 9F/ADR-026 — untouched by
 * this phase) to award real Boncuk for a canonical COMPLETED order.
 * Deliberately an asynchronous CONSUMER, never folded into
 * `onOrderCompleted.ts`'s own update-trigger transaction — mirrors
 * `reservationNotificationDelivery.ts`'s established outbox-consumer split
 * (thin `onDocumentCreated` trigger + an independently-testable business
 * function) rather than inventing a new pattern. This is NOT a second
 * completion trigger on `orders/{orderId}` — it only ever reacts to the
 * outbox record `onOrderCompleted.ts` already writes.
 *
 * **Locked scope (P2A architect decision, 2026-08-20) — "earn only from
 * server-trusted channels."** The P2A pre-implementation audit found that
 * `submitTakeawayOrder.ts`/`submitDeliveryOrder.ts`/`reservationPreorder.ts`
 * all hardcode `pricing.discount: moneyField(0)`, making `pricing.grandTotal`
 * a genuinely server-computed, client-untrusted value for those three
 * channels — but dine-in table-QR orders and staff/POS orders are written
 * with a client-computed `pricing` block `firestore.rules` never validates
 * (`PriceCalculator` is explicitly documented as "Not authoritative"). This
 * module therefore only ever earns for `channel` in
 * [LOYALTY_EARNING_ELIGIBLE_CHANNELS] — any other channel (today: `dineInQr`,
 * and any staff/POS-originated channel) is a deliberate, disclosed no-earn
 * outcome, not a bug. See `docs/business_rules.md` `BR-PRICE-002` (ROADMAP)
 * for the tracked follow-up that would make those channels eligible.
 *
 * **Security fix (2026-08-21) — channel alone is never sufficient.** A
 * security review correctly found the eligible-channel check above is not,
 * by itself, proof of trusted pricing: `firestore.rules`' `isOrgMember`
 * branch lets a staff/POS client create a direct-Firestore order with
 * `channel: 'takeaway'` or `channel: 'reservationPreorder'` (a legitimate,
 * pre-existing capability, unrelated to loyalty, that this fix does not
 * remove) — its `pricing` block for that write is entirely client-computed
 * and never server-verified. Earning now additionally requires
 * [hasServerPricingAuthority] on the order document — a `pricingAuthority`
 * marker only `submitTakeawayOrder`/`submitDeliveryOrder`/
 * `reservationPreorder` ever stamp (Admin SDK, bypasses
 * `firestore.rules`), and that `firestore.rules` explicitly forbids any
 * client create from supplying at all. See
 * `functions/src/orderPricingAuthority.ts` for the full `channel`-vs-
 * `pricingAuthority` reasoning. An eligible-channel order missing this
 * marker (a client-authored order on an eligible-looking channel, or a
 * legacy pre-P2A-security-fix order) is classified `untrusted-pricing-
 * provenance` — never earns, permanently, not merely retried later; no
 * migration back-stamps old orders as trusted.
 *
 * **Known, disclosed limitation**: no currently shipping Cloud Function or
 * client write path ever transitions a real order to `status: "completed"`
 * — only test-harness code does. This consumer is real, fully tested
 * against the existing `orderEvents`/`onOrderCompleted.ts` contract, but
 * production execution is unreachable until a canonical server-side
 * order-completion transition exists (out of scope for P2A — not built
 * here, per instruction).
 */

// -----------------------------------------------------------------------
// Earning eligibility — closed allow-list, not a blocklist. A channel not
// explicitly listed here never earns, by default, including any future
// channel introduced without this list being deliberately revisited.
// -----------------------------------------------------------------------

export const LOYALTY_EARNING_ELIGIBLE_CHANNELS = [
  "takeaway",
  "delivery",
  "reservationPreorder",
] as const;
type LoyaltyEarningEligibleChannel = (typeof LOYALTY_EARNING_ELIGIBLE_CHANNELS)[number];

function isEligibleChannel(channel: unknown): channel is LoyaltyEarningEligibleChannel {
  return (
    typeof channel === "string" &&
    (LOYALTY_EARNING_ELIGIBLE_CHANNELS as readonly string[]).includes(channel)
  );
}

/**
 * The single, isolated seam for computing the eligible net spend basis —
 * BR-LOYALTY §3: "eligible net spend after campaign/coupon discount." Today,
 * for the three eligible channels, `pricing.discount` is always
 * server-hardcoded to 0, so `grandTotal` already equals the correct basis;
 * if a future channel/phase adds a real server-computed discount,
 * `grandTotal` (gross minus discount plus fees) remains the correct basis
 * unchanged. A future Boncuk-*redemption*-paid-amount exclusion (no such
 * field exists yet — not invented here) would subtract from the value this
 * one function returns, without requiring any change to the transaction
 * that calls it — satisfying "architecture must not make future exclusion
 * impossible" without implementing that exclusion now.
 *
 * Returns `null` (never approximates) when the persisted order snapshot
 * cannot deterministically establish the basis — malformed shape, a
 * non-integer/negative amount, or a currency other than `TRY` (the only
 * currency this app uses today; a silent assumption otherwise would be
 * exactly the "silently approximate" failure mode this phase's own
 * instructions forbid).
 */
export function resolveEligibleNetSpendMinorUnits(
  orderData: FirebaseFirestore.DocumentData,
): number | null {
  const pricing = orderData.pricing;
  if (!pricing || typeof pricing !== "object") return null;
  const grandTotal = (pricing as Record<string, unknown>).grandTotal;
  if (!grandTotal || typeof grandTotal !== "object") return null;
  const minorUnits = (grandTotal as Record<string, unknown>).minorUnits;
  const currencyCode = (grandTotal as Record<string, unknown>).currencyCode;
  if (typeof minorUnits !== "number" || !Number.isInteger(minorUnits) || minorUnits < 0) {
    return null;
  }
  if (currencyCode !== "TRY") return null;
  return minorUnits;
}

export interface BoncukEarningResult {
  boncukEarned: number;
  remainderAfterMinorUnits: number;
}

/**
 * BR-LOYALTY §2 — the locked earning algorithm. Pure integer arithmetic
 * only (`Math.floor`/`%`), never floating point. A zero-eligible-spend or
 * small-eligible-spend order may legitimately earn `boncukEarned: 0` while
 * still moving the remainder forward — that is a correct, expected outcome
 * (§7), not an edge case to special-case away.
 *
 * Verified against every worked example in the locked spec:
 * (0, 54900) -> (10, 4900); (4900, 15100) -> (4, 0); (0, 2000) -> (0, 2000);
 * (4900, 100) -> (1, 0).
 */
export function calculateBoncukEarning(params: {
  previousRemainderMinorUnits: number;
  eligibleNetSpendMinorUnits: number;
}): BoncukEarningResult {
  const availableMinorUnits =
    params.previousRemainderMinorUnits + params.eligibleNetSpendMinorUnits;
  const boncukEarned = Math.floor(
    availableMinorUnits / BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK,
  );
  const remainderAfterMinorUnits =
    availableMinorUnits % BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK;
  return { boncukEarned, remainderAfterMinorUnits };
}

export interface ProcessOrderCompletionForLoyaltyEarningResult {
  processed: boolean;
  reason: string;
  boncukEarned?: number;
}

function orderEventsCollection(db: Firestore) {
  return db.collection("orderEvents");
}

/**
 * The actual business logic — called both by the trigger's fast path and
 * directly by tests, mirroring `processReservationEventForDelivery`'s own
 * pure-ish-function/thin-trigger-wrapper split.
 *
 * Cheap, pre-transaction checks (no Firestore reads needed — pure checks on
 * the event payload itself) terminate first; only a genuine earning attempt
 * opens the one atomic transaction that reads/writes the ledger entry,
 * account, and outbox flag together.
 */
export async function processOrderCompletionEventForLoyaltyEarning(
  db: Firestore,
  eventId: string,
  eventData: Record<string, unknown> | undefined,
  now: Timestamp = Timestamp.now(),
): Promise<ProcessOrderCompletionForLoyaltyEarningResult> {
  if (!eventData) return { processed: false, reason: "missing-event" };

  if (eventData.type !== "order.completed") {
    // Not an order-completion outbox record — nothing for this consumer to
    // do. Never touches rewardsEvaluated (the doc may not even have one).
    return { processed: false, reason: "not-an-order-completion-event" };
  }

  const orderId = eventData.orderId as string | undefined;
  const organizationId = eventData.organizationId as string | null | undefined;
  const customerId = eventData.customerId as string | null | undefined;
  const channel = eventData.channel as string | null | undefined;

  if (!orderId || !organizationId) {
    // A genuine data-integrity anomaly — onOrderCompleted.ts always writes
    // both fields. Log and leave rewardsEvaluated untouched (retryable),
    // never guess at a value.
    logger.error(
      `[loyaltyOrderEarning] malformed order.completed event ${eventId} — missing orderId/organizationId.`,
    );
    return { processed: false, reason: "malformed-event" };
  }

  const eventRef = orderEventsCollection(db).doc(eventId);

  if (!customerId) {
    // Guest order (dine-in QR or takeaway guest checkout) — never earns.
    await eventRef.set({ rewardsEvaluated: true }, { merge: true });
    return { processed: true, reason: "guest-order-no-customer" };
  }

  if (!isEligibleChannel(channel)) {
    // Channel pricing is not server-trusted today — a deliberate, disclosed
    // exclusion (see this file's own doc comment / BR-PRICE-002), not a
    // failure to retry.
    await eventRef.set({ rewardsEvaluated: true }, { merge: true });
    return { processed: true, reason: "channel-not-eligible-for-earning" };
  }

  const orderRef = db.collection("orders").doc(orderId);
  const membershipRef = db
    .collection(TENANT_CUSTOMERS_COLLECTION)
    .doc(`${organizationId}_${customerId}`);
  const accountRef = db.collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${customerId}`);
  const ledgerEntryId = deriveLoyaltyLedgerEntryId({
    organizationId,
    customerId,
    entryType: "orderEarn",
    sourceId: orderId,
  });
  const ledgerEntryRef = db.collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(ledgerEntryId);

  return db.runTransaction(async (tx): Promise<ProcessOrderCompletionForLoyaltyEarningResult> => {
    // Reads first, always — mirrors completeCustomerProfile.ts's
    // established transaction discipline.
    const ledgerSnap = await tx.get(ledgerEntryRef);
    if (ledgerSnap.exists) {
      // Already applied by a prior invocation (retry, or a duplicate
      // trigger delivery) — the deterministic ledger id, not the
      // rewardsEvaluated flag, is the authoritative idempotency check.
      // Re-assert the flag in case a prior attempt crashed after this
      // point but before step 8 below, then stop — never recompute.
      tx.set(eventRef, { rewardsEvaluated: true }, { merge: true });
      return { processed: true, reason: "already-applied" };
    }

    const membershipSnap = await tx.get(membershipRef);
    if (!membershipSnap.exists) {
      // A real, expected case (not a bug) — a customer can place an order
      // before completing registration/profile. No account is created, no
      // ledger entry is written.
      tx.set(eventRef, { rewardsEvaluated: true }, { merge: true });
      return { processed: true, reason: "no-tenant-membership" };
    }

    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      logger.error(`[loyaltyOrderEarning] order ${orderId} referenced by event ${eventId} not found.`);
      return { processed: false, reason: "order-document-missing" };
    }
    const orderData = orderSnap.data()!;
    if (orderData.status !== "completed") {
      logger.error(
        `[loyaltyOrderEarning] order ${orderId} is not status "completed" at read time (was "${String(orderData.status)}").`,
      );
      return { processed: false, reason: "order-not-completed-at-read-time" };
    }

    if (!hasServerPricingAuthority(orderData)) {
      // Security fix (2026-08-21) — an eligible channel is necessary but
      // never sufficient. Either a client-authored order that happens to
      // carry an eligible-looking channel (the exact attack this fix
      // closes), or a legitimate legacy order that predates this field —
      // either way, a deterministic, permanent no-earn outcome, not a
      // transient failure to retry. No ledger entry, no account mutation.
      logger.warn(
        `[loyaltyOrderEarning] order ${orderId} (channel "${channel}") is on an eligible channel but has no valid server pricing-authority marker — treating as untrusted pricing provenance, never earning.`,
      );
      tx.set(eventRef, { rewardsEvaluated: true }, { merge: true });
      return { processed: true, reason: "untrusted-pricing-provenance" };
    }

    const eligibleNetSpendMinorUnits = resolveEligibleNetSpendMinorUnits(orderData);
    if (eligibleNetSpendMinorUnits === null) {
      // The mandated "do not silently approximate" escape hatch, applied
      // per-order rather than blocking the whole feature — an eligible
      // channel whose own persisted pricing snapshot is still malformed.
      logger.error(
        `[loyaltyOrderEarning] order ${orderId} (channel "${channel}") has an untrustworthy/malformed pricing.grandTotal — cannot establish earning basis.`,
      );
      return { processed: false, reason: "untrustworthy-pricing-data" };
    }

    const accountSnap = await tx.get(accountRef);
    const existingAccount: LoyaltyAccountData = accountSnap.exists
      ? (accountSnap.data() as LoyaltyAccountData)
      : {
          organizationId,
          customerId,
          spendableBalance: 0,
          earningRemainderMinorUnits: 0,
          lifetimeEarned: 0,
          lifetimeRedeemed: 0,
          createdAt: now,
          updatedAt: now,
          revision: 0,
        };

    const { boncukEarned, remainderAfterMinorUnits } = calculateBoncukEarning({
      previousRemainderMinorUnits: existingAccount.earningRemainderMinorUnits,
      eligibleNetSpendMinorUnits,
    });

    const ledgerEntry: LoyaltyLedgerEntry = {
      organizationId,
      customerId,
      entryType: "orderEarn",
      deltaBoncuk: boncukEarned,
      sourceId: orderId,
      orderId,
      amountBasisMinorUnits: eligibleNetSpendMinorUnits,
      remainderBeforeMinorUnits: existingAccount.earningRemainderMinorUnits,
      remainderAfterMinorUnits,
      earningRateMinorUnitsPerBoncuk: BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK,
      redemptionRateMinorUnitsPerBoncuk: null,
      idempotencyKey: orderId,
      reversalOf: null,
      expiresAt: null,
      metadata: null,
    };
    // tx.create — defense-in-depth on top of the ledgerSnap.exists check
    // above: if a concurrent transaction wins a race this read somehow
    // missed, Firestore's own contention detection aborts and retries this
    // transaction, which then correctly takes the "already-applied" branch.
    tx.create(ledgerEntryRef, { ...ledgerEntry, createdAt: now });

    tx.set(accountRef, {
      organizationId: existingAccount.organizationId,
      customerId: existingAccount.customerId,
      spendableBalance: existingAccount.spendableBalance + boncukEarned,
      earningRemainderMinorUnits: remainderAfterMinorUnits,
      lifetimeEarned: existingAccount.lifetimeEarned + boncukEarned,
      lifetimeRedeemed: existingAccount.lifetimeRedeemed,
      createdAt: existingAccount.createdAt,
      updatedAt: now,
      revision: existingAccount.revision + 1,
    });

    tx.set(eventRef, { rewardsEvaluated: true }, { merge: true });

    return { processed: true, reason: "earned", boncukEarned };
  });
}

export const onOrderEventCreatedForLoyaltyEarning = onDocumentCreated(
  "orderEvents/{eventId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const db = getFirestore();
    await processOrderCompletionEventForLoyaltyEarning(
      db,
      event.params.eventId,
      snapshot.data(),
    );
  },
);
