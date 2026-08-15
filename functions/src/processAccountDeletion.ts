import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";

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
 * **Authorization (Faz D.3.2.1 — closes a REQUIRED finding: this function
 * previously had no `request.auth` check of any kind, and
 * `deletionRequests` ids are sequential/guessable
 * (`SequentialAccountDeletionRequestIdGenerator`), so any unauthenticated
 * caller who guessed or learned a `requestId` could trigger another
 * account's deletion side-effect once its cooling-off period elapsed)**:
 * this is a real-customer self-service action only — mirrors
 * `submitTakeawayOrder`'s own authenticated branch exactly
 * (`request.auth.token?.firebase?.sign_in_provider === "phone"`), the
 * canonical way this codebase already distinguishes a real, phone-
 * verified customer from an anonymous technical identity. An anonymous
 * caller (e.g. a QR guest session) can never reach this path. The account
 * actually affected is always `deletionRequests/{requestId}.uid` — a
 * server-written field `firestore.rules` already constrains to
 * `== request.auth.uid` at create time — never a client-supplied uid of
 * any kind; the caller only ever supplies the opaque `requestId`. This
 * function independently re-verifies `data.uid === request.auth.uid`
 * before doing anything else, so a real customer cannot use a guessed/
 * leaked `requestId` to process (or even confirm the existence of)
 * another customer's deletion request — a mismatch and a genuinely
 * unknown id both resolve to the same `not-found`, deliberately, so
 * this endpoint is never usable as an account/request-existence oracle.
 *
 * **Idempotent**: a request already `completed` returns
 * `{ alreadyProcessed: true }` rather than re-anonymizing or erroring —
 * safe to call twice for the same `requestId` (e.g. a retried HTTP call).
 * **Fails closed** on every other unexpected state (not found/not owned,
 * not yet due, wrong status) via `HttpsError` rather than silently
 * no-oping.
 *
 * **App Check (Faz D.3.2.1)** via `appCheckConfig.ts`'s
 * `shouldEnforceAppCheck()` — the exact same shared config every other
 * App-Check-ready Function in this codebase uses, not a new system.
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
 * "audit records retain no unnecessary PII." The Firebase Auth account
 * itself is **not** deleted by this function — only the Firestore
 * `customers/{uid}` CRM record is anonymized; a signed-out user could
 * still sign back in with the same phone number afterward. Whether the
 * Firebase Auth account itself should also be deleted is a real,
 * separate product decision this task does not make.
 */
export const processAccountDeletion = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
  if (!isRealCustomer) {
    throw new HttpsError(
      "permission-denied",
      "Account deletion requires a real, phone-verified customer identity.",
    );
  }
  const callerUid = request.auth.uid;

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

    // Ownership check — deliberately the same `not-found` a genuinely
    // unknown requestId returns above, not `permission-denied`: this
    // endpoint must never confirm or deny that a given (guessable,
    // sequential) requestId belongs to someone else.
    if (data.uid !== callerUid) {
      throw new HttpsError("not-found", "No such deletion request.");
    }

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
  },
);
