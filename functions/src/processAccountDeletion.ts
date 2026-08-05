import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";

/**
 * Processes one due account-deletion request — Sprint 9G
 * (docs/decisions.md ADR-026). An HTTPS **callable** function
 * deliberately, not a scheduled/pub-sub trigger: the kickoff's own
 * requirement is "callable/API entry points for both the Flutter app and
 * a future public web page," which is exactly what `onCall` provides (a
 * real Cloud Scheduler-driven automatic sweep is a reasonable future
 * addition, not built this sprint — see functions/README.md).
 *
 * Reaches into the `customers` collection to anonymize the CRM record —
 * something no Dart client-side code may do (this app's Firestore
 * Security Rules make `customers`/`deletionRequests` status transitions
 * server-only; a Cloud Function, using the Admin SDK, is the one trusted
 * place allowed to). This mirrors why the fuller event-chain
 * (visit-recording/reward-evaluation/stock-consumption,
 * `onOrderCompleted`'s deferred scope) belongs server-side too — this
 * function is a first, narrow instance of that same principle, not the
 * full chain.
 *
 * **Idempotent**: a request already `completed` returns
 * `{ alreadyProcessed: true }` rather than re-anonymizing or erroring —
 * safe to call twice for the same `requestId` (e.g. a retried HTTP call).
 * **Fails closed** on every other unexpected state (not found, not yet
 * due, wrong status) via `HttpsError` rather than silently no-oping.
 *
 * **Scope, stated honestly**: only the CRM `Customer` record is
 * anonymized. Media (Storage), loyalty reward history, and notification
 * preferences cascading is explicitly deferred — those Firestore
 * collections don't have a real repository (Dart or Cloud Function) yet
 * for this function to reach into; anonymizing a nonexistent real record
 * would be nothing to do, not silently skipped. Legally-required records
 * (orders, audit trails) are deliberately **not** touched — `Order
 * .customerId` remains the same `uid` string (a stable, non-PII opaque
 * reference on its own) so historical financial data stays intact,
 * matching "legally-required records retained with identity
 * minimization." The audit record this function writes carries only
 * `requestId`/a timestamp — no `uid`, phone number, or display name —
 * "audit records retain no unnecessary PII."
 */
export const processAccountDeletion = onCall(async (request) => {
  const requestId = request.data?.requestId;
  if (typeof requestId !== "string" || requestId.length === 0) {
    throw new HttpsError("invalid-argument", "requestId is required.");
  }

  const db = getFirestore();
  const requestRef = db.collection("deletionRequests").doc(requestId);

  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(requestRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "No such deletion request.");
    }
    const data = snapshot.data()!;

    if (data.status === "completed") {
      return { status: "completed", alreadyProcessed: true };
    }
    if (data.status !== "coolingOff") {
      throw new HttpsError(
        "failed-precondition",
        `Request is not due for processing (status: ${data.status}).`,
      );
    }

    const coolingOffEndsAtRaw = data.coolingOffEndsAt;
    const coolingOffEndsAt =
      typeof coolingOffEndsAtRaw?.toDate === "function"
        ? coolingOffEndsAtRaw.toDate()
        : new Date(coolingOffEndsAtRaw);
    if (new Date() < coolingOffEndsAt) {
      throw new HttpsError(
        "failed-precondition",
        "The cooling-off period has not elapsed yet.",
      );
    }

    const uid = data.uid;
    if (typeof uid === "string" && uid.length > 0) {
      const customerRef = db.collection("customers").doc(uid);
      const customerSnapshot = await tx.get(customerRef);
      if (customerSnapshot.exists) {
        tx.update(customerRef, {
          displayName: "Silinmiş Kullanıcı",
          phoneNumber: "",
          accountStatus: "restricted",
        });
      }
    }

    const now = new Date().toISOString();
    tx.update(requestRef, { status: "completed", completedAt: now });

    // PII-free audit record - requestId and a timestamp only, never uid,
    // phone number, or display name.
    tx.set(db.collection("accountDeletionAuditEvents").doc(`${requestId}-completed`), {
      requestId,
      type: "accountDeletion.completed",
      recordedAt: now,
    });

    return { status: "completed", alreadyProcessed: false };
  });
});
