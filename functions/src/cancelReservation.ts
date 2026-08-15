import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import type { Firestore, Transaction, DocumentReference, DocumentData } from "firebase-admin/firestore";
import { loadReservationPolicy } from "./reservationConfig";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import {
  resolveReservationCancellationActor,
  computeCustomerCancellationCutoff,
  type ReservationCancellationActor,
} from "./reservationCancellationAuthorization";
import { readHoldRecord, releaseHold } from "./reservationHoldOps";
import {
  readConfirmedReservationCleanupContext,
  applyConfirmedReservationCleanup,
} from "./reservationTerminalCleanup";
import { writeReservationEvent } from "./reservationEvents";
import {
  resolvePreorderOrderRef,
  buildPreorderCancellationPatch,
  isReservationPreorderReleasedToKitchen,
} from "./reservationPreorder";

/**
 * Faz R.3B — customer/staff reservation cancellation. A single callable
 * serving both actor kinds (§2's own explicit "tek callable hem customer
 * hem staff cancellation destekleyebilir, ama actor authority server-side
 * belirlenmeli" instruction) — `resolveReservationCancellationActor`
 * (`reservationCancellationAuthorization.ts`) is the sole source of "who is
 * cancelling," never a client-supplied `actorType`.
 *
 * Cancellable from all three non-terminal statuses
 * (`pendingRestaurantApproval`/`changeProposed`/`confirmed`) — each with its
 * own hold/proposal/capacity release shape (§8/§9/§10). Already-`cancelled`
 * is an idempotent no-op; every OTHER terminal status
 * (`rejected`/`completed`/`noShow`) fails closed — a terminal reservation
 * never re-enters active lifecycle (§1).
 */

const MAX_REASON_LENGTH = 500;
const DISALLOWED_REASON_CHARACTERS = /[<>]/;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function sanitizeOptionalReasonCode(raw: unknown): string | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "string") invalid("reasonCode must be a string.");
  const trimmed = (raw as string).trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > 100) invalid("reasonCode is too long.");
  return trimmed;
}

function sanitizeOptionalReason(raw: unknown): string | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "string") invalid("reason must be a string.");
  const trimmed = (raw as string).trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > MAX_REASON_LENGTH) invalid("reason is too long.");
  if (DISALLOWED_REASON_CHARACTERS.test(trimmed)) invalid("reason contains disallowed characters.");
  return trimmed;
}

async function handleCancel(
  tx: Transaction,
  db: Firestore,
  reservationRef: DocumentReference,
  reservation: DocumentData,
  actor: ReservationCancellationActor,
  now: Date,
  reasonCode: string | null,
  reason: string | null,
): Promise<Record<string, unknown>> {
  if (reservation.status === "cancelled") {
    return { reservationId: reservationRef.id, status: "cancelled", duplicate: true };
  }
  if (reservation.status === "rejected" || reservation.status === "completed" || reservation.status === "noShow") {
    throw new HttpsError(
      "failed-precondition",
      `Reservation is already terminal (status: ${reservation.status}) and cannot be cancelled.`,
    );
  }
  if (
    reservation.status !== "pendingRestaurantApproval" &&
    reservation.status !== "changeProposed" &&
    reservation.status !== "confirmed"
  ) {
    throw new HttpsError("failed-precondition", `Unexpected reservation status: ${reservation.status}.`);
  }

  // Faz R.3B §5 — customer cutoff, staff exempt entirely (§4).
  if (actor.actorType === "customer") {
    const policy = await loadReservationPolicy(tx, db, reservation.branchId as string);
    if (policy) {
      const cutoff = computeCustomerCancellationCutoff(
        reservation,
        policy.customerCancellationCutoffMinutes,
        now,
      );
      if (cutoff.cutoffReached) {
        throw new HttpsError("failed-precondition", "customerCancellationCutoffReached");
      }
    }
  }

  // ---------------------------------------------------------------
  // Reads — every one, before any write below.
  // ---------------------------------------------------------------
  const preorderOrderId = reservation.preorderOrderId as string | null | undefined;
  const preorderOrderRef = preorderOrderId ? resolvePreorderOrderRef(db, reservationRef.id) : null;
  const preorderDoc = preorderOrderRef ? await tx.get(preorderOrderRef) : null;
  const preorderReleased =
    preorderDoc && preorderDoc.exists
      ? isReservationPreorderReleasedToKitchen(preorderDoc.data()!.status as string)
      : false;

  // Faz R.3B §6 — the LOCKED business rule: a customer may never self-cancel
  // once their linked preorder has reached the kitchen. Staff always may.
  if (actor.actorType === "customer" && preorderReleased) {
    throw new HttpsError("failed-precondition", "reservationPreorderReleasedToKitchen");
  }

  let hold = null;
  let proposalRef: DocumentReference | null = null;
  let proposalDoc: FirebaseFirestore.DocumentSnapshot | null = null;
  let cleanupContext: Awaited<ReturnType<typeof readConfirmedReservationCleanupContext>> = null;

  if (reservation.status === "pendingRestaurantApproval" || reservation.status === "changeProposed") {
    const activeHoldId = reservation.activeHoldId as string | null;
    if (activeHoldId) {
      hold = readHoldRecord(await tx.get(db.collection("reservationHolds").doc(activeHoldId)));
    }
  }
  if (reservation.status === "changeProposed") {
    const activeProposalId = reservation.activeProposalId as string | null;
    if (activeProposalId) {
      proposalRef = db.collection("reservationChangeProposals").doc(activeProposalId);
      proposalDoc = await tx.get(proposalRef);
    }
  }
  if (reservation.status === "confirmed") {
    cleanupContext = await readConfirmedReservationCleanupContext(
      tx,
      db,
      reservationRef.id,
      reservation,
      now,
    );
  }

  // ---------------------------------------------------------------
  // Writes — every read above is done.
  // ---------------------------------------------------------------
  if (hold && hold.status === "active") {
    await releaseHold(tx, db, hold, now);
  }

  if (proposalRef && proposalDoc && proposalDoc.exists) {
    const proposal = proposalDoc.data()!;
    // Faz R.3B §9 — terminalize, never fake accepted/rejected. Idempotent:
    // a proposal already resolved by a race (accept/reject/expire) is left
    // exactly as-is.
    if (proposal.status === "pendingCustomerResponse") {
      tx.set(
        proposalRef,
        { status: "cancelled", respondedAt: now, cancellationReason: "parentReservationCancelled" },
        { merge: true },
      );
    }
  }

  if (cleanupContext) {
    await applyConfirmedReservationCleanup(tx, db, reservationRef.id, cleanupContext, now, {
      staffUid: actor.actorType === "staff" ? actor.actorId : null,
      closeReason: "reservationCancelled",
    });
  }

  // Faz R.3B §6 — auto-cancel only a still-pendingConfirmation preorder;
  // buildPreorderCancellationPatch itself is a no-op (returns null) for any
  // other status, so a released preorder is never touched here regardless
  // of actor — this line is reached for both customer (already fail-closed
  // above if released) and staff (deliberately never auto-cancelling a
  // released preorder, per §6's own explicit instruction).
  if (preorderOrderRef && preorderDoc) {
    const patch = buildPreorderCancellationPatch(preorderDoc, now);
    if (patch) tx.set(preorderOrderRef, patch, { merge: true });
  }

  tx.set(
    reservationRef,
    {
      status: "cancelled",
      cancelledAt: now,
      cancelledBy: actor.actorType,
      cancelledByStaffId: actor.actorType === "staff" ? actor.actorId : null,
      cancellationReasonCode: reasonCode,
      cancellationReason: reason,
      activeHoldId: null,
      activeProposalId: null,
      activeProposalProposedTime: null,
      activeProposalProposedAreaId: null,
      activeProposalCustomerResponseDeadlineAt: null,
      updatedAt: now,
    },
    { merge: true },
  );

  writeReservationEvent(tx, db, {
    eventId: `${reservationRef.id}-cancelled`,
    type: "reservationCancelled",
    reservationId: reservationRef.id,
    organizationId: reservation.organizationId as string,
    restaurantId: reservation.restaurantId as string,
    branchId: reservation.branchId as string,
    recordedAt: now,
    actor: { actorType: actor.actorType, actorId: actor.actorId },
    extra: { reasonCode, fromStatus: reservation.status },
  });

  return { reservationId: reservationRef.id, status: "cancelled", duplicate: false };
}

export const cancelReservation = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.reservationId !== "string" || data.reservationId.length === 0) {
      invalid("reservationId is required.");
    }
    const reservationId = data.reservationId as string;
    const reasonCode = sanitizeOptionalReasonCode(data.reasonCode);
    const reason = sanitizeOptionalReason(data.reason);

    const db = getFirestore();
    const reservationRef = db.collection("reservations").doc(reservationId);

    return db.runTransaction(async (tx) => {
      const reservationDoc = await tx.get(reservationRef);
      if (!reservationDoc.exists) {
        throw new HttpsError("not-found", "Reservation not found.");
      }
      const reservation = reservationDoc.data()!;

      // Faz R.3B §2/§3/§4 — canonical customer-vs-staff resolution, never a
      // client-supplied actorType.
      const actor = resolveReservationCancellationActor(request, reservation);

      const now = new Date();
      return handleCancel(tx, db, reservationRef, reservation, actor, now, reasonCode, reason);
    });
  },
);
