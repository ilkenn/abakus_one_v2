import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { getFirestore } from "firebase-admin/firestore";

/**
 * Writes a durable, exactly-once outbox record when an order reaches
 * `completed` — Sprint 9F (docs/decisions.md ADR-026), the transactional-
 * outbox half of "server-authoritative events & outbox workflows."
 *
 * **Scope, stated honestly**: this function records *that* an order
 * completed — it does not itself perform visit-recording, reward
 * evaluation, or stock consumption. Those business rules already exist as
 * real, tested Dart use cases (`RecordCustomerVisitAndEvaluateRewards`,
 * `ConsumeStockForOrder`, and related CRM/inventory logic) — reimplementing
 * that business logic a second time, in TypeScript, so a Cloud Function
 * could execute it, is a substantial undertaking of its own and is
 * deliberately deferred, not attempted partially here. What this sprint
 * *does* deliver is the real, durable, idempotent trigger point a future
 * sprint's consumer (another Cloud Function, or a scheduled processor)
 * would read from — `orderEvents/{orderId}-completed` — proven here to be
 * written exactly once even under Firestore's "at least once" trigger
 * delivery.
 *
 * Idempotency mechanism: [orderId]-completed is a **deterministic**
 * document id, and the write uses `.create()` (fails if the document
 * already exists) rather than `.set()` (would silently overwrite) — a
 * second invocation for the same order's completion hits
 * `ALREADY_EXISTS` and is caught/ignored, not treated as an error. This
 * is the same "exactly-once outbox append" guarantee
 * `GrantVisitReward`'s Dart-side idempotency-by-composite-key already
 * establishes for reward grants, applied here at the event-recording
 * layer instead.
 */
export const onOrderCompleted = onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    if (before.status === "completed" || after.status !== "completed") {
      // Only the transition *into* completed matters - not an unrelated
      // field update on an already-completed order, and not a document
      // that was already completed before this update.
      return;
    }

    const db = getFirestore();
    const eventId = `${event.params.orderId}-completed`;
    const now = new Date().toISOString();

    try {
      await db
        .collection("orderEvents")
        .doc(eventId)
        .create({
          organizationId: after.organizationId ?? null,
          orderId: event.params.orderId,
          type: "order.completed",
          channel: after.channel ?? null,
          customerId: after.customerId ?? null,
          branchId: after.branchId ?? null,
          restaurantId: after.restaurantId ?? null,
          recordedAt: now,
          // Explicit, honest markers for what a future consumer still
          // needs to do - not silently implied as already handled.
          visitRecorded: false,
          rewardsEvaluated: false,
          stockConsumed: false,
        });
    } catch (error: unknown) {
      const code = (error as { code?: number | string })?.code;
      if (code === 6 || code === "already-exists") {
        // ALREADY_EXISTS - a second trigger invocation for the same
        // completion. The outbox record already exists; this is the
        // expected, correct outcome of "exactly once," not a failure.
        return;
      }
      throw error;
    }
  }
);
