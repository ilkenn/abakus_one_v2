import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore } from "firebase-admin/firestore";
import type { Firestore } from "firebase-admin/firestore";
import { readHoldRecord, releaseHold } from "./reservationHoldOps";
import { writeReservationEvent } from "./reservationEvents";
import {
  resolvePreorderOrderRef,
  buildPreorderCancellationPatch,
  buildPreorderKdsReleasePatch,
} from "./reservationPreorder";

/**
 * Response-timeout and proposal-hold-expiry sweeps — Faz R.1B §12/§13. The
 * first `onSchedule` usage in this codebase (confirmed via grep — no prior
 * scheduled function exists to mirror). Both concerns are swept by one
 * scheduled function (`reservationSweep`) rather than two, so only one
 * Cloud Scheduler job is provisioned; each pass is independent, and neither
 * mutation is a single giant transaction — every due document gets its own
 * small transaction, re-validating its own precondition inside that
 * transaction (idempotent/retry-safe: a document already resolved by a
 * concurrent sweep run or a staff/customer action in between the query and
 * the transaction is simply skipped, never double-processed).
 *
 * **Faz R.1B §12's "challenge the requirement" analysis**: the spec's own
 * stated preference is `status: 'rejected', reasonCode:
 * 'restaurantResponseTimeout'` rather than a new terminal status (e.g.
 * `'expired'`/`'timedOut'`). That preference is followed here, and is the
 * right call, not just a default: every other reason a Reservation reaches
 * a rejected outcome (a direct staff decline) already shares the same
 * `'rejected'` status with a distinguishing `reasonCode` — there is no
 * existing precedent in this phase's own status model (Faz R.1B §1's five
 * statuses) for a reason-specific status. Carving out exactly one new
 * status for exactly one reason code, when every other reason already goes
 * through `reasonCode`, would be an arbitrary, inconsistent special case,
 * not a genuinely distinct customer- or restaurant-facing state — the
 * *outcome* (no reservation, must rebook) is identical either way. A
 * future phase that genuinely needs to treat timeouts differently (e.g.
 * restaurant-performance SLA tracking) can still filter on `reasonCode`
 * without a schema change.
 */

const SWEEP_BATCH_SIZE = 50;

function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

/** Faz R.1B §12 — releases the initial hold (if any) and terminates a Reservation whose `responseDeadlineAt` has passed while still `pendingRestaurantApproval`. Returns the number of Reservations actually resolved by this call (not merely queried — a concurrently-resolved one is skipped, not counted). */
export async function runReservationResponseTimeoutSweep(
  db: Firestore,
  now: Date,
): Promise<number> {
  const dueSnapshot = await db
    .collection("reservations")
    .where("status", "==", "pendingRestaurantApproval")
    .where("responseDeadlineAt", "<=", now)
    .limit(SWEEP_BATCH_SIZE)
    .get();

  let processed = 0;
  for (const snapshot of dueSnapshot.docs) {
    const reservationRef = snapshot.ref;
    const resolved = await db.runTransaction(async (tx) => {
      const reservationDoc = await tx.get(reservationRef);
      if (!reservationDoc.exists) return false;
      const reservation = reservationDoc.data()!;
      // Idempotent/retry-safe re-check — another sweep invocation or a
      // staff action may have already resolved this Reservation between
      // the query above and this transaction.
      if (reservation.status !== "pendingRestaurantApproval") return false;
      if (toDate(reservation.responseDeadlineAt).getTime() > now.getTime()) return false;

      // Faz R.1D.1 §12 — read before any write below (hold release), never
      // a client-supplied order id.
      const preorderOrderId = reservation.preorderOrderId as string | null | undefined;
      const preorderOrderRef = preorderOrderId
        ? resolvePreorderOrderRef(db, reservationRef.id)
        : null;
      const preorderDoc = preorderOrderRef ? await tx.get(preorderOrderRef) : null;

      const activeHoldId = reservation.activeHoldId as string | null;
      if (activeHoldId) {
        const hold = readHoldRecord(
          await tx.get(db.collection("reservationHolds").doc(activeHoldId)),
        );
        if (hold && hold.status === "active") {
          await releaseHold(tx, db, hold, now);
        }
      }

      // Faz R.1D.1 §12 — the linked preorder (if still pendingConfirmation)
      // is cancelled in this SAME transaction as the response-timeout
      // rejection, so it can never later leak to KDS.
      if (preorderOrderRef && preorderDoc) {
        const patch = buildPreorderCancellationPatch(preorderDoc, now);
        if (patch) tx.set(preorderOrderRef, patch, { merge: true });
      }

      tx.set(
        reservationRef,
        {
          status: "rejected",
          reasonCode: "restaurantResponseTimeout",
          activeHoldId: null,
          updatedAt: now,
        },
        { merge: true },
      );

      // Faz R.1B.1 — written inside this same transaction so the event
      // commits atomically with the status transition, never as a separate
      // step after the transaction resolves.
      writeReservationEvent(tx, db, {
        eventId: `${reservationRef.id}-responseTimedOut`,
        type: "reservationResponseTimedOut",
        reservationId: reservationRef.id,
        organizationId: reservation.organizationId as string,
        restaurantId: reservation.restaurantId as string,
        branchId: reservation.branchId as string,
        recordedAt: now,
      });

      return true;
    });
    if (resolved) {
      processed += 1;
    }
  }
  return processed;
}

/** Faz R.1B §13 — releases the alternative-proposal hold (if any) and expires a proposal whose `customerResponseDeadlineAt` has passed while still `pendingCustomerResponse`, returning its Reservation to `pendingRestaurantApproval` (only if the Reservation is still tracking this exact proposal as active). Returns the number of proposals actually resolved by this call. */
export async function runReservationProposalExpirySweep(
  db: Firestore,
  now: Date,
): Promise<number> {
  const dueSnapshot = await db
    .collection("reservationChangeProposals")
    .where("status", "==", "pendingCustomerResponse")
    .where("customerResponseDeadlineAt", "<=", now)
    .limit(SWEEP_BATCH_SIZE)
    .get();

  let processed = 0;
  for (const snapshot of dueSnapshot.docs) {
    const proposalRef = snapshot.ref;
    const resolved = await db.runTransaction(async (tx) => {
      const proposalDoc = await tx.get(proposalRef);
      if (!proposalDoc.exists) return false;
      const proposal = proposalDoc.data()!;
      if (proposal.status !== "pendingCustomerResponse") return false;
      if (toDate(proposal.customerResponseDeadlineAt).getTime() > now.getTime()) return false;

      const reservationRef = db.collection("reservations").doc(proposal.reservationId as string);
      const reservationDoc = await tx.get(reservationRef);
      const reservation = reservationDoc.exists ? reservationDoc.data()! : null;

      const holdId = proposal.holdId as string | undefined;
      if (holdId) {
        const hold = readHoldRecord(await tx.get(db.collection("reservationHolds").doc(holdId)));
        if (hold && hold.status === "active") {
          await releaseHold(tx, db, hold, now);
        }
      }

      tx.set(proposalRef, { status: "expired", respondedAt: now }, { merge: true });

      if (
        reservation &&
        reservation.status === "changeProposed" &&
        reservation.activeProposalId === proposalRef.id
      ) {
        tx.set(
          reservationRef,
          {
            status: "pendingRestaurantApproval",
            activeProposalId: null,
            activeHoldId: null,
            // Faz R.2 — see respondToReservation.ts's handleProposeChange
            // own comment on this denormalized snapshot.
            activeProposalProposedTime: null,
            activeProposalProposedAreaId: null,
            activeProposalCustomerResponseDeadlineAt: null,
            updatedAt: now,
          },
          { merge: true },
        );
      }

      // Faz R.1B.1 — same-transaction event write (see the timeout sweep's
      // own comment above for why).
      writeReservationEvent(tx, db, {
        eventId: `${proposal.reservationId}-changeExpired-${proposalRef.id}`,
        type: "reservationChangeExpired",
        reservationId: proposal.reservationId as string,
        organizationId: proposal.organizationId as string,
        restaurantId: proposal.restaurantId as string,
        branchId: proposal.branchId as string,
        recordedAt: now,
        extra: { proposalId: proposalRef.id },
      });

      return true;
    });
    if (resolved) {
      processed += 1;
    }
  }
  return processed;
}

export const reservationSweep = onSchedule("every 5 minutes", async () => {
  const db = getFirestore();
  const now = new Date();
  const timedOut = await runReservationResponseTimeoutSweep(db, now);
  const expired = await runReservationProposalExpirySweep(db, now);
  console.log(
    `reservationSweep: resolved ${timedOut} response-timeout(s), ${expired} proposal-expiry(ies).`,
  );
});

// -----------------------------------------------------------------------
// Scheduled preorder KDS release — Faz R.1D.2. A deliberately SEPARATE
// scheduled function, not folded into `reservationSweep` above: that
// function's own 5-minute cadence is untouched (its two concerns don't need
// finer granularity), while this one needs the 1-minute cadence the
// business rule calls for — `onSchedule` fixes one cadence per Cloud
// Function, so two different cadences genuinely need two functions.
// -----------------------------------------------------------------------

const PREORDER_KDS_RELEASE_BATCH_SIZE = 50;

/**
 * Bounded candidate query — `channel`/`status` equality plus a
 * `kitchenReleaseAtTimestamp <= now` range filter, ordered by that same
 * field (oldest-due first) so repeated runs drain a backlog in order
 * rather than the same few candidates being requeried while others starve.
 * Requires the composite index `orders(channel ASC, status ASC,
 * kitchenReleaseAtTimestamp ASC)` — see `firestore.indexes.json`. Never an
 * unbounded scan: `limit(PREORDER_KDS_RELEASE_BATCH_SIZE)`, with any
 * remaining due orders picked up by the next run (every 1 minute) —
 * mirrors `runReservationResponseTimeoutSweep`/
 * `runReservationProposalExpirySweep`'s own established shape exactly:
 * query once, then one independent, retry-safe transaction per candidate,
 * each fully re-validating its own precondition
 * (`buildPreorderKdsReleasePatch`) rather than trusting the query result.
 *
 * **Failure isolation (§13)**: a `try`/`catch` around each candidate's own
 * transaction means one corrupt/failing document can never abort the rest
 * of the batch — logged and skipped, the loop continues.
 *
 * Returns the number of preorders actually released by this call (not
 * merely queried — a concurrently-resolved or genuinely-ineligible
 * candidate is skipped, not counted).
 */
export async function runPreorderKdsReleaseSweep(db: Firestore, now: Date): Promise<number> {
  const dueSnapshot = await db
    .collection("orders")
    .where("channel", "==", "reservationPreorder")
    .where("status", "==", "pendingConfirmation")
    .where("kitchenReleaseAtTimestamp", "<=", now)
    .orderBy("kitchenReleaseAtTimestamp", "asc")
    .limit(PREORDER_KDS_RELEASE_BATCH_SIZE)
    .get();

  let processed = 0;
  for (const snapshot of dueSnapshot.docs) {
    const orderRef = snapshot.ref;
    try {
      const released = await db.runTransaction(async (tx) => {
        const orderDoc = await tx.get(orderRef);
        const reservationContextId = orderDoc.exists
          ? (orderDoc.data()!.reservationContextId as string | null | undefined)
          : null;
        const reservationDoc = reservationContextId
          ? await tx.get(db.collection("reservations").doc(reservationContextId))
          : null;

        const check = buildPreorderKdsReleasePatch(orderDoc, reservationDoc, now);
        if (!check.eligible) {
          console.log(`reservationPreorderKdsRelease: skipped ${orderRef.id} (${check.reason})`);
          return false;
        }

        tx.set(orderRef, check.patch, { merge: true });
        tx.set(db.collection("auditEvents").doc(check.auditEvent.id), check.auditEvent.data);
        return true;
      });
      if (released) processed += 1;
    } catch (error) {
      console.error(`reservationPreorderKdsRelease: failed processing ${orderRef.id}`, error);
    }
  }
  return processed;
}

export const reservationPreorderKdsRelease = onSchedule("every 1 minutes", async () => {
  const db = getFirestore();
  const now = new Date();
  const released = await runPreorderKdsReleaseSweep(db, now);
  console.log(`reservationPreorderKdsRelease: released ${released} preorder(s) to the kitchen.`);
});
