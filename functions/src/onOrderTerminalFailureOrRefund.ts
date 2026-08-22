import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { getFirestore } from "firebase-admin/firestore";

/**
 * Writes a durable, exactly-once outbox record when an order transitions
 * INTO `rejected`, `cancelled`, or `refunded` — Boncuk Loyalty Program
 * P4-C-B (2026-08-22), the terminal-failure/refund sibling of
 * `onOrderCompleted.ts`'s existing `order.completed` outbox producer.
 *
 * **Deliberately a generic, passive `onDocumentUpdated` trigger, mirroring
 * `onOrderCompleted.ts`'s exact shape — not a mechanism any status-writing
 * function has to remember to call.** P4-C-A's audit found the working
 * precedent for this outbox already exists in `onOrderCompleted.ts`, and
 * that precedent's own biggest strength is that it is decoupled from
 * *who* performs the transition: `onOrderCompleted.ts` fires correctly
 * regardless of which future canonical completion path eventually writes
 * `status: "completed"`. This trigger inherits the same property — it will
 * correctly and safely fire for `reservationPreorder`'s existing
 * `cancelReservation`/`markReservationNoShow`/`reservationSweep`-driven
 * `pendingConfirmation → cancelled` transitions TODAY (a no-op in practice,
 * since that channel cannot redeem Boncuk), and will correctly activate for
 * `takeaway`/`delivery` orders the moment a canonical reject/cancel/refund
 * transition is eventually built for them (P4-C-A §9's disclosed blocker —
 * still not built, out of this phase's own scope) — with zero further
 * change to this trigger or its consumer.
 *
 * **From-state-agnostic, by design.** `orderStatus.ts`'s own state table
 * allows `cancelled` from every non-terminal status
 * (`created`/`pendingConfirmation`/`confirmed`/`preparing`/`ready`/
 * `outForDelivery`), and `refunded` only from `completed`. This trigger
 * does not care which status the order came FROM — only that
 * `after.status` is genuinely one it did not already hold, and that it is
 * one of the three terminal-failure/refund statuses. Whether anything
 * downstream actually needs to happen is entirely the restore consumer's
 * own decision (`loyaltyRedemptionRestore.ts`), based on whether the order
 * ever carried a real `boncukRedemption` ledger entry — never this
 * trigger's concern.
 *
 * **Idempotency mechanism, identical to `onOrderCompleted.ts`**:
 * `{orderId}-{terminalStatus}` is a deterministic document id, and the
 * write uses `.create()` (fails if the document already exists) rather
 * than `.set()` — a second trigger invocation for the same transition
 * (Firestore's "at least once" delivery) hits `ALREADY_EXISTS` and is
 * caught/ignored, never treated as an error.
 *
 * **Honest, disclosed markers — not implied as already handled.**
 * `boncukRedemptionRestoreEvaluated: false` is this event's own "still
 * needs a real consumer to look at this" flag (flipped to `true` only by
 * `loyaltyRedemptionRestore.ts`, and only on a successful restore or a
 * genuine, deterministic no-op — never on an anomaly, so a retry stays
 * possible). For `refunded` specifically, `earnReversalEvaluated: false`
 * is ALSO recorded — an honest placeholder for the separate, NOT-yet-built
 * `orderEarnReversal` consumer (P4-C-A §3's explicit instruction: redemption
 * restoration and earned-Boncuk reversal are two independent accounting
 * events and must never be merged into one). This file makes no claim that
 * either has actually run — it only records that both are now owed.
 *
 * This trigger does not modify `onOrderCompleted.ts` in any way — the two
 * are independent, co-registered triggers on the same `orders/{orderId}`
 * path, exactly how Firestore Functions v2 already supports multiple
 * independent consumers of one document's updates.
 */

const TERMINAL_FAILURE_OR_REFUND_STATUSES = ["rejected", "cancelled", "refunded"] as const;
type TerminalFailureOrRefundStatus = (typeof TERMINAL_FAILURE_OR_REFUND_STATUSES)[number];

function isTerminalFailureOrRefundStatus(
  value: unknown,
): value is TerminalFailureOrRefundStatus {
  return (
    typeof value === "string" &&
    (TERMINAL_FAILURE_OR_REFUND_STATUSES as readonly string[]).includes(value)
  );
}

export const onOrderTerminalFailureOrRefund = onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    if (before.status === after.status || !isTerminalFailureOrRefundStatus(after.status)) {
      // Only a genuine transition INTO one of the three terminal
      // failure/refund statuses matters — not an unrelated field update,
      // and not a document that already held that status before this
      // update (mirrors onOrderCompleted.ts's own guard exactly).
      return;
    }
    const terminalStatus = after.status;

    const db = getFirestore();
    const eventId = `${event.params.orderId}-${terminalStatus}`;
    const now = new Date().toISOString();

    const doc: Record<string, unknown> = {
      organizationId: after.organizationId ?? null,
      orderId: event.params.orderId,
      type: `order.${terminalStatus}`,
      channel: after.channel ?? null,
      customerId: after.customerId ?? null,
      branchId: after.branchId ?? null,
      restaurantId: after.restaurantId ?? null,
      recordedAt: now,
      boncukRedemptionRestoreEvaluated: false,
    };
    if (terminalStatus === "refunded") {
      doc.earnReversalEvaluated = false;
    }

    try {
      await db.collection("orderEvents").doc(eventId).create(doc);
    } catch (error: unknown) {
      const code = (error as { code?: number | string })?.code;
      if (code === 6 || code === "already-exists") {
        // ALREADY_EXISTS — a second trigger invocation for the same
        // transition. The outbox record already exists; this is the
        // expected, correct outcome of "exactly once," not a failure.
        return;
      }
      throw error;
    }
  },
);
