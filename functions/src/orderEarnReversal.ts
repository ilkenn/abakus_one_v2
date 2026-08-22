import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import type { Firestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
  type LoyaltyLedgerEntry,
} from "./loyaltyLedger";
import { calculateFullOrderEarningReversal } from "./loyaltyReversalMath";
import { parseCarryComponent, formatCarryComponent, type BoncukFraction } from "./loyaltyPolicy";
import type { LoyaltyAccountData } from "./getCustomerLoyaltySnapshot";

/**
 * `orderEarnReversal` — Boncuk Loyalty Program P4-D-B (2026-08-22).
 *
 * Consumes `onOrderTerminalFailureOrRefund.ts`'s `order.refunded` outbox
 * records to claw back Boncuk previously EARNED by an order that has since
 * been refunded (`order.status == "refunded"` now means an authorized
 * manager+ has confirmed the money was actually, completely returned —
 * see `refundTakeawayOrder.ts`'s own doc comment). Deliberately an
 * asynchronous CONSUMER, never folded into the terminal-transition trigger
 * itself, and deliberately a SEPARATE consumer from
 * `loyaltyRedemptionRestore.ts` — a single refunded order may independently
 * have both a `boncukRedemption` to restore AND an `orderEarn` to reverse;
 * neither consumer knows about the other, and both transactionally read/
 * write the same `loyaltyAccounts` document, so Firestore's own contention
 * handling — never an in-process lock or ordering assumption — is what
 * keeps the final account state correct regardless of which consumer's
 * transaction commits first.
 *
 * **Ignores every event type except `order.refunded`.** `order.rejected`/
 * `order.cancelled` never reach `completed` in the first place (the
 * canonical transition table forbids it), so there is structurally never
 * an `orderEarn` entry to reverse for those — this consumer does not even
 * attempt to look one up for them.
 *
 * **O(1) math only — never a ledger replay, never today's policy.** Uses
 * `loyaltyReversalMath.ts`'s existing, already-proven
 * `calculateFullOrderEarningReversal` verbatim. This file's only job is to
 * (a) find the ONE original `orderEarn` entry by its deterministic id,
 * (b) load the account's current O(1) projection fields, (c) call that
 * pure function, and (d) apply its result transactionally with the same
 * idempotency discipline every other ledger writer in this codebase uses.
 *
 * **Why "no `orderEarn` entry exists" is a SAFE no-op here, not a bug.**
 * This is only true because of `loyaltyOrderEarning.ts`'s own P4-D-B race
 * fix: that consumer now re-reads the canonical order status INSIDE its
 * own earning transaction and refuses to create an `orderEarn` entry once
 * the order is `refunded`. Because that check and this consumer's own
 * check both key off the SAME canonical `orders/{orderId}.status` field,
 * and Firestore's optimistic-concurrency conflict/retry serializes any
 * transaction pair that touches the same document, there is no execution
 * order in which an `orderEarn` entry could appear for this order AFTER
 * this consumer has already concluded "missing, nothing to reverse" — the
 * absence, once observed for a genuinely `refunded` order, is permanent.
 * Without that other fix, this branch would be an unsafe race window
 * instead of a proven no-op; the two fixes are one causal unit, documented
 * on both sides.
 */

export interface ProcessOrderRefundEventForOrderEarnReversalResult {
  processed: boolean;
  reason: string;
  clawbackBoncuk?: number;
}

function orderEventsCollection(db: Firestore) {
  return db.collection("orderEvents");
}

/**
 * Validates the ORIGINAL `orderEarn` ledger entry's provenance before ever
 * trusting its snapshotted ratio/basis as reversal input — mirrors
 * `loyaltyRedemptionRestore.ts`'s own `resolveOriginalRedemptionForRestore`
 * exactly, adapted to the earning-family field shape. A missing entry is
 * its own distinct, expected, SAFE outcome (see this file's own doc
 * comment on why); a malformed one fails closed rather than guessing.
 */
type ResolvedOriginalOrderEarn =
  | {
      status: "ok";
      amountBasisMinorUnits: number;
      earningSpendMinorUnits: number;
      earningBoncukAmount: number;
    }
  | { status: "missing" }
  | { status: "malformed" };

function resolveOriginalOrderEarnForReversal(
  snap: FirebaseFirestore.DocumentSnapshot,
  organizationId: string,
  customerId: string,
  orderId: string,
): ResolvedOriginalOrderEarn {
  if (!snap.exists) return { status: "missing" };
  const raw = snap.data()!;

  if (raw.entryType !== "orderEarn") return { status: "malformed" };
  if (raw.organizationId !== organizationId) return { status: "malformed" };
  if (raw.customerId !== customerId) return { status: "malformed" };
  if (raw.orderId !== orderId) return { status: "malformed" };
  if (raw.sourceId !== orderId) return { status: "malformed" };

  const amountBasisMinorUnits = raw.amountBasisMinorUnits;
  const earningSpendMinorUnits = raw.earningSpendMinorUnits;
  const earningBoncukAmount = raw.earningBoncukAmount;
  if (
    typeof amountBasisMinorUnits !== "number" ||
    !Number.isInteger(amountBasisMinorUnits) ||
    amountBasisMinorUnits < 0
  ) {
    return { status: "malformed" };
  }
  if (
    typeof earningSpendMinorUnits !== "number" ||
    !Number.isInteger(earningSpendMinorUnits) ||
    earningSpendMinorUnits <= 0
  ) {
    return { status: "malformed" };
  }
  if (
    typeof earningBoncukAmount !== "number" ||
    !Number.isInteger(earningBoncukAmount) ||
    earningBoncukAmount <= 0
  ) {
    return { status: "malformed" };
  }

  return { status: "ok", amountBasisMinorUnits, earningSpendMinorUnits, earningBoncukAmount };
}

/**
 * Validates exactly the fields this reversal transaction reads and
 * mutates (`spendableBalance`/`boncukDebt`/`validOrderEntitlementBoncuk`/
 * `earningCarryNumerator`/`earningCarryDenominator`/`organizationId`/
 * `customerId`/`revision`) — mirrors `loyaltyRedemption.ts`'s own
 * `resolveAccountForRedemption`, extended with the three
 * earning-projection fields a reversal additionally needs. A missing
 * account is anomalous (an `orderEarn` entry cannot exist without the
 * account that received its credit having existed) and fails closed
 * rather than being treated as a zero account.
 */
type ResolvedAccountForReversal =
  | { status: "ok"; account: LoyaltyAccountData }
  | { status: "missing-loyalty-account" }
  | { status: "inconsistent-loyalty-account-state" };

function resolveAccountForReversal(
  accountSnap: FirebaseFirestore.DocumentSnapshot,
): ResolvedAccountForReversal {
  if (!accountSnap.exists) {
    return { status: "missing-loyalty-account" };
  }
  const raw = accountSnap.data()!;
  const isValidNonNegativeInt = (value: unknown): value is number =>
    typeof value === "number" && Number.isInteger(value) && value >= 0;
  const isNonEmptyString = (value: unknown): value is string =>
    typeof value === "string" && value.length > 0;

  if (
    !isValidNonNegativeInt(raw.spendableBalance) ||
    !isValidNonNegativeInt(raw.boncukDebt) ||
    !isValidNonNegativeInt(raw.validOrderEntitlementBoncuk) ||
    !isValidNonNegativeInt(raw.lifetimeEarned) ||
    !isValidNonNegativeInt(raw.lifetimeRedeemed) ||
    !isValidNonNegativeInt(raw.revision) ||
    !isNonEmptyString(raw.earningCarryNumerator) ||
    !isNonEmptyString(raw.earningCarryDenominator) ||
    !isNonEmptyString(raw.organizationId) ||
    !isNonEmptyString(raw.customerId)
  ) {
    return { status: "inconsistent-loyalty-account-state" };
  }
  return { status: "ok", account: raw as LoyaltyAccountData };
}

/**
 * The actual business logic — called both by the trigger's fast path and
 * directly by tests, mirroring every other outbox consumer in this
 * codebase's pure-ish-function/thin-trigger-wrapper split.
 *
 * `earnReversalEvaluated` is set to `true` ONLY on a genuine success or a
 * deterministic no-op (guest order, no original earning to reverse,
 * already-reversed retry) — never on an anomaly (missing order, status
 * mismatch, malformed provenance, malformed account, reversal-math
 * failure), so those stay retryable rather than silently swallowed —
 * mirrors `loyaltyRedemptionRestore.ts`'s own discipline exactly.
 */
export async function processOrderRefundEventForOrderEarnReversal(
  db: Firestore,
  eventId: string,
  eventData: Record<string, unknown> | undefined,
  now: Timestamp = Timestamp.now(),
): Promise<ProcessOrderRefundEventForOrderEarnReversalResult> {
  if (!eventData) return { processed: false, reason: "missing-event" };

  if (eventData.type !== "order.refunded") {
    // This consumer reacts ONLY to a confirmed refund — never
    // order.completed, order.rejected, or order.cancelled. Never touches
    // earnReversalEvaluated (the doc may not even carry that field for
    // those event types).
    return { processed: false, reason: "not-a-refund-event" };
  }

  const orderId = eventData.orderId as string | undefined;
  const organizationId = eventData.organizationId as string | null | undefined;
  const customerId = eventData.customerId as string | null | undefined;

  if (!orderId || !organizationId) {
    // A genuine data-integrity anomaly — onOrderTerminalFailureOrRefund.ts
    // always writes both fields. Log and leave the event untouched
    // (retryable), never guess at a value.
    logger.error(
      `[orderEarnReversal] malformed order.refunded event ${eventId} — missing orderId/organizationId.`,
    );
    return { processed: false, reason: "malformed-event" };
  }

  const eventRef = orderEventsCollection(db).doc(eventId);

  if (!customerId) {
    // Guest order — Boncuk can never be earned by a guest identity, so
    // there is structurally nothing to reverse. A deterministic no-op,
    // correctly marked evaluated.
    await eventRef.set({ earnReversalEvaluated: true }, { merge: true });
    return { processed: true, reason: "guest-order-no-customer" };
  }

  const orderRef = db.collection("orders").doc(orderId);
  const originalOrderEarnRef = db
    .collection(LOYALTY_LEDGER_ENTRIES_COLLECTION)
    .doc(
      deriveLoyaltyLedgerEntryId({
        organizationId,
        customerId,
        entryType: "orderEarn",
        sourceId: orderId,
      }),
    );
  const reversalEntryRef = db
    .collection(LOYALTY_LEDGER_ENTRIES_COLLECTION)
    .doc(
      deriveLoyaltyLedgerEntryId({
        organizationId,
        customerId,
        entryType: "orderEarnReversal",
        sourceId: orderId,
      }),
    );
  const accountRef = db.collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${customerId}`);

  return db.runTransaction(
    async (tx): Promise<ProcessOrderRefundEventForOrderEarnReversalResult> => {
      // Reads first, always.
      const reversalSnap = await tx.get(reversalEntryRef);
      if (reversalSnap.exists) {
        // Already reversed by a prior invocation (retry, or a duplicate
        // trigger delivery) — the deterministic reversal-entry id, not the
        // evaluated flag, is the authoritative idempotency check.
        // Re-assert the flag in case a prior attempt crashed after
        // creating the reversal entry but before this point, then stop —
        // never a second clawback, never a second debt/carry change.
        tx.set(eventRef, { earnReversalEvaluated: true }, { merge: true });
        return { processed: true, reason: "already-reversed" };
      }

      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        logger.error(
          `[orderEarnReversal] order ${orderId} referenced by event ${eventId} not found.`,
        );
        return { processed: false, reason: "order-document-missing" };
      }
      const orderData = orderSnap.data()!;

      // Defense-in-depth — re-verify the REAL current order document
      // agrees with what the trusted event claims, never trust the event
      // alone. Never reverse from a forged/stale/mismatched event.
      if (orderData.status !== "refunded") {
        logger.error(
          `[orderEarnReversal] order ${orderId} status mismatch for event ${eventId} — event claims "refunded", document reads "${String(orderData.status)}".`,
        );
        return { processed: false, reason: "order-status-mismatch" };
      }
      if (orderData.organizationId !== organizationId || orderData.customerId !== customerId) {
        logger.error(
          `[orderEarnReversal] order ${orderId} organizationId/customerId mismatch against event ${eventId}.`,
        );
        return { processed: false, reason: "order-identity-mismatch" };
      }

      const originalSnap = await tx.get(originalOrderEarnRef);
      const originalResult = resolveOriginalOrderEarnForReversal(
        originalSnap,
        organizationId,
        customerId,
        orderId,
      );
      if (originalResult.status === "missing") {
        // No Boncuk was ever earned on this order (or it never reached
        // `completed` before being refunded) — nothing to reverse. Safe
        // ONLY because of loyaltyOrderEarning.ts's own P4-D-B race fix —
        // see this file's own doc comment for the full causal proof. A
        // deterministic no-op, correctly marked evaluated.
        tx.set(eventRef, { earnReversalEvaluated: true }, { merge: true });
        return { processed: true, reason: "no-earning-to-reverse" };
      }
      if (originalResult.status === "malformed") {
        logger.error(
          `[orderEarnReversal] order ${orderId}'s original orderEarn ledger entry has malformed provenance — failing closed rather than guessing at a reversal.`,
        );
        return { processed: false, reason: "malformed-original-orderearn-entry" };
      }

      const accountSnap = await tx.get(accountRef);
      const accountResult = resolveAccountForReversal(accountSnap);
      if (accountResult.status === "missing-loyalty-account") {
        logger.error(
          `[orderEarnReversal] loyalty account ${organizationId}_${customerId} is missing — cannot reverse earning that required it to have existed.`,
        );
        return { processed: false, reason: "missing-loyalty-account" };
      }
      if (accountResult.status === "inconsistent-loyalty-account-state") {
        logger.error(
          `[orderEarnReversal] loyalty account ${organizationId}_${customerId} is in an inconsistent state — failing closed rather than guessing.`,
        );
        return { processed: false, reason: "inconsistent-loyalty-account-state" };
      }
      const account = accountResult.account;

      let currentCarry: BoncukFraction;
      try {
        currentCarry = {
          numerator: parseCarryComponent(
            account.earningCarryNumerator,
            "loyaltyAccounts.earningCarryNumerator",
          ),
          denominator: parseCarryComponent(
            account.earningCarryDenominator,
            "loyaltyAccounts.earningCarryDenominator",
          ),
        };
      } catch (err) {
        logger.error(
          `[orderEarnReversal] account ${organizationId}_${customerId} has a malformed earningCarry — failing closed. ${String(err)}`,
        );
        return { processed: false, reason: "malformed-account-carry" };
      }

      let reversal;
      try {
        reversal = calculateFullOrderEarningReversal({
          currentValidOrderEntitlementBoncuk: account.validOrderEntitlementBoncuk,
          currentCarry,
          originalEligibleSpendMinorUnits: originalResult.amountBasisMinorUnits,
          originalEarningSpendMinorUnits: originalResult.earningSpendMinorUnits,
          originalEarningBoncukAmount: originalResult.earningBoncukAmount,
          spendableBalance: account.spendableBalance,
          boncukDebt: account.boncukDebt,
        });
      } catch (err) {
        // A data-integrity signal (e.g. this order's own contribution no
        // longer fits inside the account's current total exact
        // entitlement) — fail closed rather than applying a guessed
        // clawback. Left unevaluated so this is retried/investigated, not
        // silently accepted.
        logger.error(
          `[orderEarnReversal] reversal math failed for order ${orderId}, account ${organizationId}_${customerId} — failing closed. ${String(err)}`,
        );
        return { processed: false, reason: "reversal-math-failed" };
      }

      const originalEntry = originalSnap.data()!;
      const reversalEntry: LoyaltyLedgerEntry = {
        organizationId,
        customerId,
        entryType: "orderEarnReversal",
        entitlementDeltaBoncuk: 0 - reversal.requiredClawbackBoncuk,
        spendableDeltaBoncuk: 0 - reversal.spendableRemovedBoncuk,
        debtDeltaBoncuk: reversal.debtIncreaseBoncuk,
        sourceId: orderId,
        orderId,
        // Historical earning provenance, copied VERBATIM from the original
        // entry — never re-derived from today's policy or account state.
        amountBasisMinorUnits: originalResult.amountBasisMinorUnits,
        earningCarryNumeratorBefore: formatCarryComponent(currentCarry.numerator),
        earningCarryDenominatorBefore: formatCarryComponent(currentCarry.denominator),
        earningCarryNumeratorAfter: formatCarryComponent(reversal.newCarry.numerator),
        earningCarryDenominatorAfter: formatCarryComponent(reversal.newCarry.denominator),
        earningSpendMinorUnits: originalResult.earningSpendMinorUnits,
        earningBoncukAmount: originalResult.earningBoncukAmount,
        loyaltyPolicyVersion: (originalEntry.loyaltyPolicyVersion as number | null) ?? null,
        debtBeforeBoncuk: account.boncukDebt,
        debtAfterBoncuk: reversal.newBoncukDebt,
        redemptionValueMinorUnitsPerBoncuk: null,
        maxRedemptionBasisPoints: null,
        idempotencyKey: orderId,
        reversalOf: originalOrderEarnRef.id,
        expiresAt: null,
        metadata: null,
      };

      // Write phase — every tx.get() this transaction will ever perform
      // has already happened above.
      tx.create(reversalEntryRef, { ...reversalEntry, createdAt: now });

      tx.set(accountRef, {
        ...account,
        validOrderEntitlementBoncuk: reversal.newValidOrderEntitlementBoncuk,
        earningCarryNumerator: formatCarryComponent(reversal.newCarry.numerator),
        earningCarryDenominator: formatCarryComponent(reversal.newCarry.denominator),
        spendableBalance: reversal.newSpendableBalance,
        boncukDebt: reversal.newBoncukDebt,
        // lifetimeEarned/lifetimeRedeemed/organizationId/customerId/
        // createdAt all preserved exactly — a reversal never touches any
        // of them (lifetimeEarned is monotonic by design, see
        // loyaltyOrderEarning.ts's own doc comment).
        revision: account.revision + 1,
        updatedAt: now,
      });

      tx.set(eventRef, { earnReversalEvaluated: true }, { merge: true });

      return { processed: true, reason: "reversed", clawbackBoncuk: reversal.requiredClawbackBoncuk };
    },
  );
}

export const onOrderEventCreatedForOrderEarnReversal = onDocumentCreated(
  "orderEvents/{eventId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const db = getFirestore();
    await processOrderRefundEventForOrderEarnReversal(db, event.params.eventId, snapshot.data());
  },
);
