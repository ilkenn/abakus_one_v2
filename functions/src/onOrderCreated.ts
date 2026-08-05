import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { canTransition, isOrderStatus } from "./orderStatus";

/**
 * Server-authoritative `created -> pendingConfirmation` transition —
 * Sprint 9F (docs/decisions.md ADR-026).
 *
 * `firestore.rules`'s `orders` collection allows a client `create` only
 * while `status == 'created'`; every subsequent transition is
 * `allow update: if false` — status changes are Cloud-Function-only. This
 * closes the exact gap Sprint 9E's `FirestoreCanonicalOrderRepository`
 * left open: the Dart client (`SubmitPosOrder`/`SubmitCustomerOrder`)
 * still performs its own `created -> pendingConfirmation` transition
 * client-side before writing (unchanged, still tested, still correct for
 * the emulator-only development flow this sprint verifies) — against a
 * *real* deployed project, this function is what would actually move a
 * freshly created order out of `created`, independent of what the client
 * claims. It is intentionally the *only* status this function ever sets;
 * every other transition (confirmed, preparing, ready, ...) is staff/
 * kitchen-initiated and is explicitly out of this sprint's scope (see
 * functions/README.md's "not yet implemented" list).
 *
 * Idempotent by construction, not by a separate dedup record: Firestore
 * triggers can fire more than once for the same create event ("at least
 * once" delivery). This function only acts when the document's *current*
 * status is still `created` — a second invocation for the same order
 * finds `pendingConfirmation` already set and no-ops instead of
 * re-appending a duplicate status-history entry.
 */
export const onOrderCreated = onDocumentCreated(
  "orders/{orderId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    if (!data || data.status !== "created") {
      // Either malformed (missing status) or already past `created` -
      // nothing for this function to do. Never guesses at a status.
      return;
    }
    if (!canTransition("created", "pendingConfirmation")) {
      // Defensive - the table itself guarantees this today, but a
      // function must never assume a transition it doesn't itself check.
      return;
    }

    const db = getFirestore();
    const ref = snapshot.ref;
    const now = new Date().toISOString();
    const auditEntryId = `${event.params.orderId}-transition-server-1`;

    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(ref);
      const freshData = fresh.data();
      if (!freshData || freshData.status !== "created") {
        // Re-checked inside the transaction - another invocation (or a
        // race with a future manual transition) already moved this
        // order past `created`. Never overwrite a status this function
        // didn't itself decide.
        return;
      }
      if (!isOrderStatus(freshData.status)) return;

      const statusHistory = Array.isArray(freshData.statusHistory)
        ? freshData.statusHistory
        : [];

      tx.update(ref, {
        status: "pendingConfirmation",
        version: FieldValue.increment(1),
        statusHistory: [
          ...statusHistory,
          {
            id: auditEntryId,
            type: "statusChange",
            description: "Status changed from created to pendingConfirmation",
            actor: "system",
            timestamp: now,
            previousValue: "created",
            newValue: "pendingConfirmation",
          },
        ],
      });

      const organizationId = freshData.organizationId;
      if (typeof organizationId === "string") {
        tx.set(db.collection("auditEvents").doc(auditEntryId), {
          organizationId,
          type: "order.statusChanged",
          orderId: event.params.orderId,
          previousValue: "created",
          newValue: "pendingConfirmation",
          actor: "system",
          timestamp: now,
        });
      }
    });
  }
);
