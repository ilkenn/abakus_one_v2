import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import type { Firestore, Transaction, DocumentReference, DocumentData } from "firebase-admin/firestore";
import { isMinuteAligned } from "./reservationAvailability";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { readHoldRecord, releaseHold, consumeHold } from "./reservationHoldOps";
import { writeReservationEvent } from "./reservationEvents";
import { resolvePreorderOrderRef, buildPreorderConfirmationPatch } from "./reservationPreorder";

/**
 * Customer-side response to a restaurant's alternative-time/area proposal —
 * Faz R.1B. Real phone-auth required, exactly like `submitReservation.ts`'s
 * own `isRealCustomer` gate — no arbitrary `customerId` is ever accepted
 * from the client; ownership is always `reservation.customerId ===
 * request.auth.uid`, the verified identity.
 */

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

type HandlerResult = Record<string, unknown>;

async function handleAccept(
  tx: Transaction,
  db: Firestore,
  reservationRef: DocumentReference,
  reservation: DocumentData,
  proposalRef: DocumentReference,
  proposal: DocumentData,
  now: Date,
): Promise<HandlerResult> {
  if (proposal.status === "accepted") {
    return { reservationId: reservationRef.id, proposalId: proposalRef.id, status: "confirmed", duplicate: true };
  }
  if (proposal.status === "rejected") {
    throw new HttpsError("failed-precondition", "This proposal has already been rejected.");
  }
  if (proposal.status === "expired") {
    throw new HttpsError("failed-precondition", "This proposal has expired and can no longer be accepted.");
  }
  if (proposal.status !== "pendingCustomerResponse") {
    throw new HttpsError("failed-precondition", `Unexpected proposal status: ${proposal.status}.`);
  }
  if (reservation.status !== "changeProposed" || reservation.activeProposalId !== proposalRef.id) {
    throw new HttpsError(
      "failed-precondition",
      "This proposal is no longer the reservation's active proposal.",
    );
  }

  // Faz R.1D.1 §10 — read before any write below (hold consumption), never
  // a client-supplied order id.
  const preorderOrderId = reservation.preorderOrderId as string | null | undefined;
  const preorderOrderRef = preorderOrderId ? resolvePreorderOrderRef(db, reservationRef.id) : null;
  const preorderDoc = preorderOrderRef ? await tx.get(preorderOrderRef) : null;

  // Faz R.1B §9 — hold integrity re-verified independently, fail-closed,
  // never trusted purely because the proposal's own status still reads
  // `pendingCustomerResponse` (mirrors Faz R.0.3's own race-safety
  // precedent: check the hold's own `expiresAt` against server time
  // directly, never the aggregate/status alone).
  const hold = readHoldRecord(await tx.get(db.collection("reservationHolds").doc(proposal.holdId)));
  if (!hold || hold.status !== "active") {
    throw new HttpsError("failed-precondition", "The hold for this proposal is no longer active.");
  }
  if (hold.expiresAt.getTime() <= now.getTime()) {
    throw new HttpsError(
      "failed-precondition",
      "This proposal has expired and can no longer be accepted.",
    );
  }

  // Faz R.0.7 §2 minute-alignment invariant — re-validated, not assumed,
  // even though `proposedTime` was already validated when the proposal was
  // created.
  const proposedTime = toDate(proposal.proposedTime);
  if (!isMinuteAligned(proposedTime)) {
    throw new HttpsError("internal", "Stored proposedTime is not minute-aligned.");
  }

  await consumeHold(tx, db, hold, now);

  // Faz R.1D.1 §10 — same transaction as the proposal-accept transition;
  // proposedTime is the new confirmedTime, so the release timing is
  // recomputed against it exactly like a direct confirm. Faz R.1D.2 — the
  // patch and its (possible) auditEvents record commit atomically.
  if (preorderOrderRef && preorderDoc) {
    const result = buildPreorderConfirmationPatch(preorderDoc, proposedTime, now);
    if (result) {
      tx.set(preorderOrderRef, result.patch, { merge: true });
      if (result.auditEvent) {
        tx.set(db.collection("auditEvents").doc(result.auditEvent.id), result.auditEvent.data);
      }
    }
  }

  tx.set(proposalRef, { status: "accepted", respondedAt: now }, { merge: true });
  tx.set(
    reservationRef,
    {
      status: "confirmed",
      confirmedTime: proposal.proposedTime,
      confirmedAreaId: proposal.proposedAreaId,
      activeHoldId: null,
      activeProposalId: null,
      // Faz R.2 — the denormalized proposal snapshot (respondToReservation
      // .ts's own handleProposeChange) is cleared once resolved, never
      // left stale on a reservation that's no longer changeProposed.
      activeProposalProposedTime: null,
      activeProposalProposedAreaId: null,
      activeProposalCustomerResponseDeadlineAt: null,
      updatedAt: now,
    },
    { merge: true },
  );

  writeReservationEvent(tx, db, {
    eventId: `${reservationRef.id}-changeAccepted-${proposalRef.id}`,
    type: "reservationChangeAccepted",
    reservationId: reservationRef.id,
    organizationId: reservation.organizationId,
    restaurantId: reservation.restaurantId,
    branchId: reservation.branchId,
    recordedAt: now,
    extra: { proposalId: proposalRef.id },
  });

  return {
    reservationId: reservationRef.id,
    proposalId: proposalRef.id,
    status: "confirmed",
    duplicate: false,
  };
}

async function handleReject(
  tx: Transaction,
  db: Firestore,
  reservationRef: DocumentReference,
  reservation: DocumentData,
  proposalRef: DocumentReference,
  proposal: DocumentData,
  now: Date,
): Promise<HandlerResult> {
  if (proposal.status === "rejected") {
    return {
      reservationId: reservationRef.id,
      proposalId: proposalRef.id,
      status: "pendingRestaurantApproval",
      duplicate: true,
    };
  }
  if (proposal.status === "accepted") {
    throw new HttpsError("failed-precondition", "This proposal has already been accepted.");
  }
  if (proposal.status === "expired") {
    throw new HttpsError("failed-precondition", "This proposal has already expired.");
  }
  if (proposal.status !== "pendingCustomerResponse") {
    throw new HttpsError("failed-precondition", `Unexpected proposal status: ${proposal.status}.`);
  }
  if (reservation.status !== "changeProposed" || reservation.activeProposalId !== proposalRef.id) {
    throw new HttpsError(
      "failed-precondition",
      "This proposal is no longer the reservation's active proposal.",
    );
  }

  const hold = readHoldRecord(await tx.get(db.collection("reservationHolds").doc(proposal.holdId)));
  if (hold && hold.status === "active") {
    await releaseHold(tx, db, hold, now);
  }

  tx.set(proposalRef, { status: "rejected", respondedAt: now }, { merge: true });
  tx.set(
    reservationRef,
    {
      // Faz R.1B §10 — explicitly NOT terminal. The restaurant may propose
      // again, attempt a direct confirm, or reject outright.
      status: "pendingRestaurantApproval",
      activeProposalId: null,
      activeHoldId: null,
      // Faz R.2 — see handleAccept's own identical comment.
      activeProposalProposedTime: null,
      activeProposalProposedAreaId: null,
      activeProposalCustomerResponseDeadlineAt: null,
      updatedAt: now,
    },
    { merge: true },
  );

  writeReservationEvent(tx, db, {
    eventId: `${reservationRef.id}-changeRejected-${proposalRef.id}`,
    type: "reservationChangeRejected",
    reservationId: reservationRef.id,
    organizationId: reservation.organizationId,
    restaurantId: reservation.restaurantId,
    branchId: reservation.branchId,
    recordedAt: now,
    extra: { proposalId: proposalRef.id },
  });

  return {
    reservationId: reservationRef.id,
    proposalId: proposalRef.id,
    status: "pendingRestaurantApproval",
    duplicate: false,
  };
}

export const respondToProposedChange = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Responding to a reservation change proposal requires a phone-verified identity.",
      );
    }
    const uid = request.auth.uid;

    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.reservationId !== "string" || data.reservationId.length === 0) {
      invalid("reservationId is required.");
    }
    if (typeof data.proposalId !== "string" || data.proposalId.length === 0) {
      invalid("proposalId is required.");
    }
    if (data.action !== "accept" && data.action !== "reject") {
      invalid("action must be 'accept' or 'reject'.");
    }
    const reservationId = data.reservationId as string;
    const proposalId = data.proposalId as string;
    const action = data.action as "accept" | "reject";

    const db = getFirestore();
    const reservationRef = db.collection("reservations").doc(reservationId);
    const proposalRef = db.collection("reservationChangeProposals").doc(proposalId);

    // Faz R.1B.1 — the corresponding reservationEvent is written by
    // `writeReservationEvent` inside this same transaction (see
    // handleAccept/handleReject), so it commits atomically with the state
    // transition, never as a separate step after `runTransaction` resolves.
    return db.runTransaction(async (tx) => {
      const reservationDoc = await tx.get(reservationRef);
      if (!reservationDoc.exists) {
        throw new HttpsError("not-found", "Reservation not found.");
      }
      const reservation = reservationDoc.data()!;
      // No arbitrary customerId from the client — ownership is always the
      // caller's own verified uid against the stored, server-written value.
      if (reservation.customerId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "You may only respond to your own reservation's proposal.",
        );
      }

      const proposalDoc = await tx.get(proposalRef);
      if (!proposalDoc.exists) {
        throw new HttpsError("not-found", "Proposal not found.");
      }
      const proposal = proposalDoc.data()!;
      if (proposal.reservationId !== reservationId) {
        throw new HttpsError(
          "failed-precondition",
          "This proposal does not belong to the specified reservation.",
        );
      }

      const now = new Date();

      if (action === "accept") {
        return handleAccept(tx, db, reservationRef, reservation, proposalRef, proposal, now);
      }
      return handleReject(tx, db, reservationRef, reservation, proposalRef, proposal, now);
    });
  },
);
