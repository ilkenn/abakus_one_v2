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
import { resolveAccountForRedemption } from "./loyaltyRedemption";
import { applyBoncukCreditDebtFirst } from "./loyaltyAccounting";

/**
 * `loyaltyRedemptionRestore` — Boncuk Loyalty Program P4-C-B (2026-08-22).
 *
 * Consumes `onOrderTerminalFailureOrRefund.ts`'s `order.rejected`/
 * `order.cancelled`/`order.refunded` outbox records to restore a
 * previously spent Boncuk redemption when its order does not (or no
 * longer does) end in a valid sale — the design P4-C-A audited and
 * P4-C-A.1 corrected (debt-first), now implemented. Deliberately an
 * asynchronous CONSUMER, never folded into the terminal-transition trigger
 * itself — mirrors `loyaltyOrderEarning.ts`'s own established
 * thin-trigger/pure-function outbox-consumer split (itself modeled on
 * `reservationNotificationDelivery.ts`'s), not a new pattern.
 *
 * **Never fabricates a redemption from order pricing fields.** The sole
 * source of truth for "was Boncuk redeemed on this order, and how much" is
 * the ORIGINAL, immutable `boncukRedemption`-entryType ledger entry,
 * looked up by its own deterministic id — never the order document's own
 * (denormalized, but not authoritative for THIS purpose) `boncukRedemption`
 * snapshot field. If no such ledger entry exists, there is structurally
 * nothing to restore — a clean, deterministic no-op (P4-C-A Case D), not a
 * special-cased skip.
 *
 * **Debt-first (P4-C-A.1's accepted correction).** The restored credit is
 * applied via `loyaltyAccounting.ts`'s shared `applyBoncukCreditDebtFirst`
 * — the exact same primitive `loyaltyOrderEarning.ts` uses for newly-earned
 * Boncuk, never a second, redemption-specific copy of the same formula.
 * This is what keeps the account invariant (`spendableBalance >= 0`,
 * `boncukDebt >= 0`, `spendableBalance > 0 ⟹ boncukDebt == 0`) intact
 * regardless of whether the restored credit originates from THIS order's
 * own redemption or lands against completely unrelated pre-existing debt.
 *
 * **Policy-version-safe by construction.** The restored Boncuk COUNT is
 * read directly from the original entry's `spendableDeltaBoncuk` (an
 * exact, immutable, already-integer historical fact) — never recomputed
 * from `valueMinorUnits`/any currently-active `loyaltyPolicies` document.
 * A policy change between the original redemption and this restore has
 * zero effect on the restored count (P4-C-A §7 / P4-C-A.1's own explicit
 * requirement).
 *
 * **Idempotent via a second deterministic ledger id.** The restore entry's
 * own id (`entryType: "boncukRedemptionRestore"`, `sourceId: orderId`) is
 * checked for existence before doing any work, and the write itself uses
 * `tx.create()` (defense-in-depth on top of that check) — a duplicate
 * trigger delivery, or the SAME terminal order-status update somehow
 * producing two outbox records, can never double-credit an account.
 *
 * **Defense-in-depth against a forged/stale/mismatched event.** The real
 * `orders/{orderId}` document is re-read INSIDE the restoring transaction
 * and its CURRENT `status`/`organizationId`/`customerId` are required to
 * agree with what the event claims — an event is routing data, trusted
 * only because `onOrderTerminalFailureOrRefund.ts` itself reads it
 * straight from the trigger's own `after` snapshot, but this consumer
 * never assumes the order hasn't changed again since.
 *
 * **`order.refunded` handling is deliberately narrow.** This consumer ONLY
 * ever restores a `boncukRedemptionRestore` entry — it never performs an
 * `orderEarnReversal` (the separate accounting event for Boncuk the SAME
 * order may have earned before being refunded). `earnReversalEvaluated`
 * (written by `onOrderTerminalFailureOrRefund.ts`) is never touched here;
 * that field is reserved for a future, independent consumer this phase
 * does not build (P4-C-A §3/§9's explicit instruction — never merge the
 * two accounting events).
 */

export interface ProcessOrderTerminalEventForBoncukRedemptionRestoreResult {
  processed: boolean;
  reason: string;
  restoredBoncuk?: number;
}

const TERMINAL_EVENT_TYPE_TO_ORDER_STATUS: Record<string, string> = {
  "order.rejected": "rejected",
  "order.cancelled": "cancelled",
  "order.refunded": "refunded",
};

function orderEventsCollection(db: Firestore) {
  return db.collection("orderEvents");
}

/**
 * Validates the ORIGINAL `boncukRedemption` ledger entry's provenance
 * before ever trusting it as the restored Boncuk count's source — §8's
 * exact required checks. Fails closed (`"malformed"`) on any violation
 * rather than guessing at a reconstruction; a missing entry is its own
 * distinct, expected outcome (`"missing"` — see this file's own doc
 * comment on never fabricating a redemption).
 */
type ResolvedOriginalRedemption =
  | { status: "ok"; restoredBoncuk: number }
  | { status: "missing" }
  | { status: "malformed" };

function resolveOriginalRedemptionForRestore(
  snap: FirebaseFirestore.DocumentSnapshot,
  organizationId: string,
  customerId: string,
  orderId: string,
): ResolvedOriginalRedemption {
  if (!snap.exists) return { status: "missing" };
  const raw = snap.data()!;

  if (raw.entryType !== "boncukRedemption") return { status: "malformed" };
  if (raw.organizationId !== organizationId) return { status: "malformed" };
  if (raw.customerId !== customerId) return { status: "malformed" };
  if (raw.orderId !== orderId) return { status: "malformed" };
  if (raw.sourceId !== orderId) return { status: "malformed" };
  if (raw.entitlementDeltaBoncuk !== 0) return { status: "malformed" };
  if (raw.debtDeltaBoncuk !== 0) return { status: "malformed" };

  const spendableDeltaBoncuk = raw.spendableDeltaBoncuk;
  if (
    typeof spendableDeltaBoncuk !== "number" ||
    !Number.isInteger(spendableDeltaBoncuk) ||
    spendableDeltaBoncuk >= 0
  ) {
    return { status: "malformed" };
  }

  const restoredBoncuk = 0 - spendableDeltaBoncuk;
  if (!Number.isInteger(restoredBoncuk) || restoredBoncuk <= 0) {
    return { status: "malformed" };
  }

  return { status: "ok", restoredBoncuk };
}

/**
 * The actual business logic — called both by the trigger's fast path and
 * directly by tests, mirroring `processOrderCompletionEventForLoyaltyEarning`'s
 * own pure-ish-function/thin-trigger-wrapper split.
 *
 * `boncukRedemptionRestoreEvaluated` is set to `true` ONLY on a genuine
 * success or a deterministic no-op (guest order, no original redemption,
 * already-restored retry) — never on an anomaly (missing order, status
 * mismatch, malformed provenance, malformed account), so those stay
 * retryable rather than silently swallowed (§11's explicit requirement).
 */
export async function processOrderTerminalEventForBoncukRedemptionRestore(
  db: Firestore,
  eventId: string,
  eventData: Record<string, unknown> | undefined,
  now: Timestamp = Timestamp.now(),
): Promise<ProcessOrderTerminalEventForBoncukRedemptionRestoreResult> {
  if (!eventData) return { processed: false, reason: "missing-event" };

  const type = eventData.type as string | undefined;
  const expectedOrderStatus = type ? TERMINAL_EVENT_TYPE_TO_ORDER_STATUS[type] : undefined;
  if (!expectedOrderStatus) {
    // Not a terminal-failure/refund event this consumer reacts to (e.g.
    // order.completed, or any other future event type) — ignore safely,
    // never touching boncukRedemptionRestoreEvaluated (the doc may not
    // even carry that field).
    return { processed: false, reason: "not-a-terminal-failure-or-refund-event" };
  }

  const orderId = eventData.orderId as string | undefined;
  const organizationId = eventData.organizationId as string | null | undefined;
  const customerId = eventData.customerId as string | null | undefined;

  if (!orderId || !organizationId) {
    // A genuine data-integrity anomaly — onOrderTerminalFailureOrRefund.ts
    // always writes both fields. Log and leave the event untouched
    // (retryable), never guess at a value.
    logger.error(
      `[loyaltyRedemptionRestore] malformed ${type} event ${eventId} — missing orderId/organizationId.`,
    );
    return { processed: false, reason: "malformed-event" };
  }

  const eventRef = orderEventsCollection(db).doc(eventId);

  if (!customerId) {
    // Guest order — Boncuk can never be redeemed by a guest identity (P4-B
    // locked rule), so there is structurally nothing to restore. A
    // deterministic no-op, correctly marked evaluated.
    await eventRef.set({ boncukRedemptionRestoreEvaluated: true }, { merge: true });
    return { processed: true, reason: "guest-order-no-customer" };
  }

  const orderRef = db.collection("orders").doc(orderId);
  const originalRedemptionRef = db
    .collection(LOYALTY_LEDGER_ENTRIES_COLLECTION)
    .doc(
      deriveLoyaltyLedgerEntryId({
        organizationId,
        customerId,
        entryType: "boncukRedemption",
        sourceId: orderId,
      }),
    );
  const restoreEntryRef = db
    .collection(LOYALTY_LEDGER_ENTRIES_COLLECTION)
    .doc(
      deriveLoyaltyLedgerEntryId({
        organizationId,
        customerId,
        entryType: "boncukRedemptionRestore",
        sourceId: orderId,
      }),
    );
  const accountRef = db.collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${customerId}`);

  return db.runTransaction(
    async (tx): Promise<ProcessOrderTerminalEventForBoncukRedemptionRestoreResult> => {
      // Reads first, always.
      const restoreSnap = await tx.get(restoreEntryRef);
      if (restoreSnap.exists) {
        // Already restored by a prior invocation (retry, or a duplicate
        // trigger delivery) — the deterministic restore-entry id, not the
        // evaluated flag, is the authoritative idempotency check.
        // Re-assert the flag in case a prior attempt crashed after
        // creating the restore entry but before this point, then stop —
        // never a second credit, never a second debt payment.
        tx.set(eventRef, { boncukRedemptionRestoreEvaluated: true }, { merge: true });
        return { processed: true, reason: "already-restored" };
      }

      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        logger.error(
          `[loyaltyRedemptionRestore] order ${orderId} referenced by event ${eventId} not found.`,
        );
        return { processed: false, reason: "order-document-missing" };
      }
      const orderData = orderSnap.data()!;

      // Defense-in-depth (§5) — re-verify the REAL current order document
      // agrees with what the trusted event claims, never trust the event
      // alone. Never restore from a forged/stale/mismatched event.
      if (orderData.status !== expectedOrderStatus) {
        logger.error(
          `[loyaltyRedemptionRestore] order ${orderId} status mismatch for event ${eventId} — event claims "${expectedOrderStatus}", document reads "${String(orderData.status)}".`,
        );
        return { processed: false, reason: "order-status-mismatch" };
      }
      if (orderData.organizationId !== organizationId || orderData.customerId !== customerId) {
        logger.error(
          `[loyaltyRedemptionRestore] order ${orderId} organizationId/customerId mismatch against event ${eventId}.`,
        );
        return { processed: false, reason: "order-identity-mismatch" };
      }

      const originalSnap = await tx.get(originalRedemptionRef);
      const originalResult = resolveOriginalRedemptionForRestore(
        originalSnap,
        organizationId,
        customerId,
        orderId,
      );
      if (originalResult.status === "missing") {
        // No Boncuk was ever redeemed on this order — nothing to restore.
        // A deterministic no-op, correctly marked evaluated (§6).
        tx.set(eventRef, { boncukRedemptionRestoreEvaluated: true }, { merge: true });
        return { processed: true, reason: "no-redemption-to-restore" };
      }
      if (originalResult.status === "malformed") {
        logger.error(
          `[loyaltyRedemptionRestore] order ${orderId}'s original boncukRedemption ledger entry has malformed provenance — failing closed rather than guessing at a restored count.`,
        );
        return { processed: false, reason: "malformed-original-redemption-entry" };
      }
      const restoredBoncuk = originalResult.restoredBoncuk;
      const originalEntry = originalSnap.data()!;

      const accountSnap = await tx.get(accountRef);
      const accountResult = resolveAccountForRedemption(accountSnap);
      if (accountResult.status === "missing-loyalty-account") {
        logger.error(
          `[loyaltyRedemptionRestore] loyalty account ${organizationId}_${customerId} is missing — cannot restore a redemption that required it to have existed.`,
        );
        return { processed: false, reason: "missing-loyalty-account" };
      }
      if (accountResult.status === "inconsistent-loyalty-account-state") {
        logger.error(
          `[loyaltyRedemptionRestore] loyalty account ${organizationId}_${customerId} is in an inconsistent state — failing closed rather than guessing.`,
        );
        return { processed: false, reason: "inconsistent-loyalty-account-state" };
      }
      const account = accountResult.account;

      // Debt-first (P4-C-A.1) — the shared primitive, never a second copy
      // of the formula.
      const { debtPaidBoncuk, spendableCreditBoncuk, newSpendableBalance, newBoncukDebt } =
        applyBoncukCreditDebtFirst({
          creditedBoncuk: restoredBoncuk,
          spendableBalance: account.spendableBalance,
          boncukDebt: account.boncukDebt,
        });

      const restoreEntry: LoyaltyLedgerEntry = {
        organizationId,
        customerId,
        entryType: "boncukRedemptionRestore",
        entitlementDeltaBoncuk: 0,
        spendableDeltaBoncuk: spendableCreditBoncuk,
        // `0 - x` rather than unary `-x` — avoids IEEE-754 negative zero,
        // matching loyaltyOrderEarning.ts's own established convention.
        debtDeltaBoncuk: 0 - debtPaidBoncuk,
        sourceId: orderId,
        orderId,
        // Historical redemption provenance, copied VERBATIM from the
        // original entry — never re-resolved from today's policy (§10).
        amountBasisMinorUnits: (originalEntry.amountBasisMinorUnits as number | null) ?? null,
        earningCarryNumeratorBefore: null,
        earningCarryDenominatorBefore: null,
        earningCarryNumeratorAfter: null,
        earningCarryDenominatorAfter: null,
        earningSpendMinorUnits: null,
        earningBoncukAmount: null,
        loyaltyPolicyVersion: (originalEntry.loyaltyPolicyVersion as number | null) ?? null,
        debtBeforeBoncuk: account.boncukDebt,
        debtAfterBoncuk: newBoncukDebt,
        redemptionValueMinorUnitsPerBoncuk:
          (originalEntry.redemptionValueMinorUnitsPerBoncuk as number | null) ?? null,
        maxRedemptionBasisPoints: (originalEntry.maxRedemptionBasisPoints as number | null) ?? null,
        idempotencyKey: orderId,
        reversalOf: originalRedemptionRef.id,
        expiresAt: null,
        metadata: null,
      };

      // Write phase — every tx.get() this transaction will ever perform
      // has already happened above.
      tx.create(restoreEntryRef, { ...restoreEntry, createdAt: now });

      tx.set(accountRef, {
        ...account,
        spendableBalance: newSpendableBalance,
        boncukDebt: newBoncukDebt,
        // lifetimeRedeemed/lifetimeEarned/validOrderEntitlementBoncuk/
        // earningCarryNumerator/earningCarryDenominator/createdAt all
        // preserved exactly — a restore never touches any of them.
        revision: account.revision + 1,
        updatedAt: now,
      });

      tx.set(eventRef, { boncukRedemptionRestoreEvaluated: true }, { merge: true });

      return { processed: true, reason: "restored", restoredBoncuk };
    },
  );
}

export const onOrderEventCreatedForLoyaltyRedemptionRestore = onDocumentCreated(
  "orderEvents/{eventId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const db = getFirestore();
    await processOrderTerminalEventForBoncukRedemptionRestore(
      db,
      event.params.eventId,
      snapshot.data(),
    );
  },
);
