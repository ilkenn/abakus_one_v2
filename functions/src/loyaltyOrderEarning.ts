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
 * `loyaltyOrderEarning` — Boncuk Loyalty Program P2A (2026-08-20), security
 * fix 2026-08-21, aggregate/debt-based rewrite P2B-B (2026-08-22).
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
 * server-trusted channels."** See [LOYALTY_EARNING_ELIGIBLE_CHANNELS] and
 * `docs/business_rules.md` `BR-LOYALTY-012`.
 *
 * **Security fix (2026-08-21) — channel alone is never sufficient.**
 * Earning additionally requires [hasServerPricingAuthority] on the order
 * document. See `functions/src/orderPricingAuthority.ts` and
 * `BR-LOYALTY-013`.
 *
 * **P2B-B aggregate/debt rewrite (2026-08-22).** `loyaltyAccounts.
 * orderEligibleNetSpendMinorUnits` is now canonical, persisted, cumulative
 * state — not just its remainder. This is mathematically equivalent to
 * P2A's original remainder-only formula for the earning direction
 * (`floor((a+b)/n) = floor(a/n) + floor((a mod n + b)/n)` is a standard
 * integer identity) — every P2A worked example is reproduced identically
 * — but a reversal (not built this phase) needs the actual aggregate, not
 * just its remainder, to recompute a new floor after subtracting a
 * specific order's contribution. `boncukDebt` is now debt-first repaid by
 * any positive `grossBoncukEarned` before any of it becomes spendable —
 * `BR-LOYALTY-014`. See `docs/decisions.md`'s P2B-A/P2B-A.1/P2B-B entries
 * for the full design and `BR-LOYALTY-016` for the three-first-class-delta
 * ledger contract this file now writes.
 *
 * **Known, disclosed limitation**: no currently shipping Cloud Function or
 * client write path ever transitions a real order to `status: "completed"`
 * — only test-harness code does. This consumer is real, fully tested
 * against the existing `orderEvents`/`onOrderCompleted.ts` contract, but
 * production execution is unreachable until a canonical server-side
 * order-completion transition exists (out of scope here).
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
 * BR-LOYALTY §3: "eligible net spend after campaign/coupon discount." See
 * the P2A doc comment history for the full reasoning — unchanged by P2B-B.
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

export interface OrderEarningCalculation {
  newAggregateMinorUnits: number;
  newRemainderMinorUnits: number;
  oldEntitlementBoncuk: number;
  newEntitlementBoncuk: number;
  grossBoncukEarned: number;
}

/**
 * BR-LOYALTY §2 / BR-LOYALTY-015 — the locked, aggregate-based earning
 * algorithm (P2B-B). Pure integer arithmetic only (`Math.floor`/`%`),
 * never floating point. A zero-eligible-spend or small-eligible-spend
 * order may legitimately earn `grossBoncukEarned: 0` while still moving
 * the aggregate/remainder forward — that is a correct, expected outcome
 * (BR-LOYALTY §7), not an edge case to special-case away.
 *
 * Verified against every worked example in the locked spec:
 * (0, 54900) -> aggregate 54900, entitlement 10, remainder 4900;
 * (54900, 15100) -> aggregate 70000, entitlement 14, gross 4, remainder 0;
 * (0, 2000) -> aggregate 2000, entitlement 0, remainder 2000.
 */
export function calculateOrderEarning(params: {
  previousAggregateMinorUnits: number;
  eligibleNetSpendMinorUnits: number;
}): OrderEarningCalculation {
  const oldAggregate = params.previousAggregateMinorUnits;
  const newAggregate = oldAggregate + params.eligibleNetSpendMinorUnits;
  const oldEntitlementBoncuk = Math.floor(oldAggregate / BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK);
  const newEntitlementBoncuk = Math.floor(newAggregate / BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK);
  return {
    newAggregateMinorUnits: newAggregate,
    newRemainderMinorUnits: newAggregate % BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK,
    oldEntitlementBoncuk,
    newEntitlementBoncuk,
    grossBoncukEarned: newEntitlementBoncuk - oldEntitlementBoncuk,
  };
}

export interface DebtAwareEarningResult {
  debtPaidBoncuk: number;
  spendableCreditBoncuk: number;
  newDebtBoncuk: number;
}

/** BR-LOYALTY-014 — future earning pays down existing debt before any of it becomes spendable. */
export function applyDebtFirst(params: {
  grossBoncukEarned: number;
  boncukDebt: number;
}): DebtAwareEarningResult {
  const debtPaidBoncuk = Math.min(params.grossBoncukEarned, params.boncukDebt);
  return {
    debtPaidBoncuk,
    spendableCreditBoncuk: params.grossBoncukEarned - debtPaidBoncuk,
    newDebtBoncuk: params.boncukDebt - debtPaidBoncuk,
  };
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
 * Reads the existing account (if any) for the earning transaction,
 * tolerating a legacy pre-P2B document by safely backfilling the two new
 * fields ONLY when every other field already reads as an untouched zero
 * account — otherwise fails closed rather than guessing at a
 * reconstruction of `orderEligibleNetSpendMinorUnits` (e.g. never assumes
 * `aggregate = lifetimeEarned * 5000`, which would silently discard
 * remainder/provenance). This codebase has no shipping order-completion
 * trigger yet, so no real non-zero legacy account can exist in production
 * today — this is defensive-in-depth for test/fixture data and any future
 * migration, not a path expected to fire against real customers.
 */
type AccountForEarning =
  | { status: "ok"; account: LoyaltyAccountData }
  | { status: "inconsistent-legacy-account-state" };

function resolveAccountForEarning(
  accountSnap: FirebaseFirestore.DocumentSnapshot,
  organizationId: string,
  customerId: string,
  now: Timestamp,
): AccountForEarning {
  if (!accountSnap.exists) {
    return {
      status: "ok",
      account: {
        organizationId,
        customerId,
        spendableBalance: 0,
        boncukDebt: 0,
        orderEligibleNetSpendMinorUnits: 0,
        earningRemainderMinorUnits: 0,
        lifetimeEarned: 0,
        lifetimeRedeemed: 0,
        createdAt: now,
        updatedAt: now,
        revision: 0,
      },
    };
  }

  const raw = accountSnap.data()!;
  const hasAggregate = typeof raw.orderEligibleNetSpendMinorUnits === "number";
  const hasDebt = typeof raw.boncukDebt === "number";
  if (hasAggregate && hasDebt) {
    return { status: "ok", account: raw as LoyaltyAccountData };
  }

  // Legacy (pre-P2B) account missing one or both new fields. Safe to
  // backfill to zero ONLY if every other field already reads as an
  // untouched, never-mutated zero account.
  const looksUntouched =
    raw.spendableBalance === 0 &&
    raw.earningRemainderMinorUnits === 0 &&
    raw.lifetimeEarned === 0 &&
    raw.lifetimeRedeemed === 0;
  if (!looksUntouched) {
    return { status: "inconsistent-legacy-account-state" };
  }
  return {
    status: "ok",
    account: {
      ...(raw as LoyaltyAccountData),
      orderEligibleNetSpendMinorUnits: raw.orderEligibleNetSpendMinorUnits ?? 0,
      boncukDebt: raw.boncukDebt ?? 0,
    },
  };
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
      // carry an eligible-looking channel, or a legitimate legacy order
      // that predates this field — either way, a deterministic, permanent
      // no-earn outcome, not a transient failure to retry.
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
    const resolvedAccount = resolveAccountForEarning(accountSnap, organizationId, customerId, now);
    if (resolvedAccount.status === "inconsistent-legacy-account-state") {
      logger.error(
        `[loyaltyOrderEarning] account ${organizationId}_${customerId} has non-zero legacy loyalty state but is missing the P2B orderEligibleNetSpendMinorUnits/boncukDebt fields — failing closed rather than guessing at a reconstruction.`,
      );
      return { processed: false, reason: "inconsistent-legacy-account-state" };
    }
    const existingAccount = resolvedAccount.account;

    const orderEligibleNetSpendBeforeMinorUnits = existingAccount.orderEligibleNetSpendMinorUnits;
    const debtBeforeBoncuk = existingAccount.boncukDebt;

    const calc = calculateOrderEarning({
      previousAggregateMinorUnits: orderEligibleNetSpendBeforeMinorUnits,
      eligibleNetSpendMinorUnits,
    });
    const { debtPaidBoncuk, spendableCreditBoncuk, newDebtBoncuk } = applyDebtFirst({
      grossBoncukEarned: calc.grossBoncukEarned,
      boncukDebt: debtBeforeBoncuk,
    });

    const ledgerEntry: LoyaltyLedgerEntry = {
      organizationId,
      customerId,
      entryType: "orderEarn",
      entitlementDeltaBoncuk: calc.grossBoncukEarned,
      spendableDeltaBoncuk: spendableCreditBoncuk,
      // `0 - x` rather than unary `-x` — avoids IEEE-754 negative zero
      // (`-0`) when debtPaidBoncuk is 0; `assert.strictEqual`/Firestore
      // both distinguish -0 from 0, and a signed ledger field should never
      // carry that distinction.
      debtDeltaBoncuk: 0 - debtPaidBoncuk,
      sourceId: orderId,
      orderId,
      amountBasisMinorUnits: eligibleNetSpendMinorUnits,
      orderEligibleNetSpendBeforeMinorUnits,
      orderEligibleNetSpendAfterMinorUnits: calc.newAggregateMinorUnits,
      orderEntitlementBeforeBoncuk: calc.oldEntitlementBoncuk,
      orderEntitlementAfterBoncuk: calc.newEntitlementBoncuk,
      remainderBeforeMinorUnits: orderEligibleNetSpendBeforeMinorUnits % BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK,
      remainderAfterMinorUnits: calc.newRemainderMinorUnits,
      earningRateMinorUnitsPerBoncuk: BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK,
      debtBeforeBoncuk,
      debtAfterBoncuk: newDebtBoncuk,
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
      spendableBalance: existingAccount.spendableBalance + spendableCreditBoncuk,
      boncukDebt: newDebtBoncuk,
      orderEligibleNetSpendMinorUnits: calc.newAggregateMinorUnits,
      earningRemainderMinorUnits: calc.newRemainderMinorUnits,
      lifetimeEarned: existingAccount.lifetimeEarned + calc.grossBoncukEarned,
      lifetimeRedeemed: existingAccount.lifetimeRedeemed,
      createdAt: existingAccount.createdAt,
      updatedAt: now,
      revision: existingAccount.revision + 1,
    });

    tx.set(eventRef, { rewardsEvaluated: true }, { merge: true });

    return { processed: true, reason: "earned", boncukEarned: calc.grossBoncukEarned };
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
