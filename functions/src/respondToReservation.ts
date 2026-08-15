import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import type { Firestore, Transaction, DocumentReference, DocumentData } from "firebase-admin/firestore";
import { resolveActiveReservationBranch, resolveReservationArea } from "./reservationScope";
import { MINIMUM_ADVANCE_MINUTES } from "./reservationConfig";
import { isMinuteAligned, checkAreaCapacity } from "./reservationAvailability";
import { isWithinBookingHorizon } from "./reservationTimezone";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireReservationManagerPermission } from "./reservationAuthorization";
import { readHoldRecord, releaseHold, consumeHold, claimConfirmedCapacityDirectly } from "./reservationHoldOps";
import { writeReservationEvent } from "./reservationEvents";
import {
  resolvePreorderOrderRef,
  buildPreorderConfirmationPatch,
  buildPreorderCancellationPatch,
} from "./reservationPreorder";

/**
 * Staff-side reservation response — Faz R.1B (`docs/decisions.md` ADR-027
 * Faz R.1B design). Server-authoritative staff action mirroring
 * `submitReservation.ts`'s own transaction/idempotency shape: a single
 * `db.runTransaction`, an idempotency-by-current-state check performed
 * first, `tx.get()` for every authoritative read (Faz R.1A.1 REQUIRED fix
 * #1's own rule, applied to this callable too).
 *
 * **Scope, explicitly**: confirm / reject / propose-an-alternative-time-or-
 * area only. No physical table assignment, no QR T-20, no preorder/KDS
 * release — those remain later phases' work, per this phase's own explicit
 * instruction.
 */

const MAX_REASON_LENGTH = 500;
const DISALLOWED_REASON_CHARACTERS = /[<>]/;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

function sanitizeReasonCode(raw: unknown): string {
  if (raw === undefined || raw === null) return "restaurantDeclined";
  if (typeof raw !== "string" || raw.trim().length === 0) invalid("reasonCode must be a non-empty string.");
  const trimmed = (raw as string).trim();
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

type HandlerResult = Record<string, unknown>;

async function handleConfirm(
  tx: Transaction,
  db: Firestore,
  reservationRef: DocumentReference,
  reservation: DocumentData,
  staffUid: string,
  now: Date,
): Promise<HandlerResult> {
  if (reservation.status === "confirmed") {
    return { reservationId: reservationRef.id, status: "confirmed", duplicate: true };
  }
  if (reservation.status !== "pendingRestaurantApproval") {
    throw new HttpsError(
      "failed-precondition",
      `Reservation is not pending restaurant approval (current status: ${reservation.status}).`,
    );
  }
  const responseDeadlineAt = toDate(reservation.responseDeadlineAt);
  if (responseDeadlineAt.getTime() <= now.getTime()) {
    throw new HttpsError(
      "failed-precondition",
      "The response window for this reservation has already closed.",
    );
  }

  const requestedTime = toDate(reservation.requestedTime);
  if (!isMinuteAligned(requestedTime)) {
    throw new HttpsError("internal", "Stored requestedTime is not minute-aligned.");
  }

  // Faz R.1D.1 §9 — read before any write below (hold consumption/capacity
  // claim), never a client-supplied order id: resolved purely from the
  // reservation's own stored, immutable preorderOrderId.
  const preorderOrderId = reservation.preorderOrderId as string | null | undefined;
  const preorderOrderRef = preorderOrderId ? resolvePreorderOrderRef(db, reservationRef.id) : null;
  const preorderDoc = preorderOrderRef ? await tx.get(preorderOrderRef) : null;

  const activeHoldId = reservation.activeHoldId as string | null;
  const hold = activeHoldId
    ? readHoldRecord(await tx.get(db.collection("reservationHolds").doc(activeHoldId)))
    : null;
  const holdUsable = hold !== null && hold.status === "active" && hold.expiresAt.getTime() > now.getTime();

  if (holdUsable) {
    await consumeHold(tx, db, hold!, now);
  } else {
    // Hold missing/expired/wrong-status — fresh, transaction-safe capacity
    // re-check (Faz R.1B §3/§4: a full-at-submission reservation can still
    // confirm later if capacity has since opened).
    const scope = await resolveActiveReservationBranch(tx, db, {
      restaurantId: reservation.restaurantId,
      branchId: reservation.branchId,
    });
    if (scope.status !== "valid") {
      throw new HttpsError("failed-precondition", "This branch is no longer accepting reservations.");
    }
    const area = await resolveReservationArea(tx, db, {
      branchId: reservation.branchId,
      areaId: reservation.requestedAreaId,
    });
    if (area.status !== "valid") {
      throw new HttpsError(
        "failed-precondition",
        "The requested reservation area is no longer available.",
      );
    }
    const endTime = new Date(
      requestedTime.getTime() + scope.policy!.reservationDurationMinutes * 60_000,
    );
    const capacity = await checkAreaCapacity(db, tx, {
      branchId: reservation.branchId,
      areaId: reservation.requestedAreaId,
      areaCapacity: area.capacity!,
      start: requestedTime,
      end: endTime,
      slotIntervalMinutes: scope.policy!.slotIntervalMinutes,
      partySize: reservation.partySize,
    });
    if (!capacity.available) {
      throw new HttpsError(
        "failed-precondition",
        "Capacity is no longer available for this reservation's requested time.",
      );
    }
    claimConfirmedCapacityDirectly(tx, db, {
      branchId: reservation.branchId,
      areaId: reservation.requestedAreaId,
      areaCapacity: area.capacity!,
      buckets: capacity.buckets,
      partySize: reservation.partySize,
    });
  }

  // Faz R.1D.1 §9 — same transaction as the reservation's own confirm
  // transition; never a partial commit where the reservation confirms but
  // a linked preorder stays stale-pending. Faz R.1D.2 — the patch and its
  // (possible) auditEvents record commit atomically, same transaction.
  if (preorderOrderRef && preorderDoc) {
    const result = buildPreorderConfirmationPatch(preorderDoc, requestedTime, now);
    if (result) {
      tx.set(preorderOrderRef, result.patch, { merge: true });
      if (result.auditEvent) {
        tx.set(db.collection("auditEvents").doc(result.auditEvent.id), result.auditEvent.data);
      }
    }
  }

  tx.set(
    reservationRef,
    {
      status: "confirmed",
      confirmedTime: reservation.requestedTime,
      confirmedAreaId: reservation.requestedAreaId,
      activeHoldId: null,
      respondedByStaffId: staffUid,
      updatedAt: now,
    },
    { merge: true },
  );

  writeReservationEvent(tx, db, {
    eventId: `${reservationRef.id}-confirmed`,
    type: "reservationConfirmed",
    reservationId: reservationRef.id,
    organizationId: reservation.organizationId,
    restaurantId: reservation.restaurantId,
    branchId: reservation.branchId,
    recordedAt: now,
  });

  return { reservationId: reservationRef.id, status: "confirmed", duplicate: false };
}

async function handleReject(
  tx: Transaction,
  db: Firestore,
  reservationRef: DocumentReference,
  reservation: DocumentData,
  staffUid: string,
  now: Date,
  reasonCode: string,
  reason: string | null,
): Promise<HandlerResult> {
  if (reservation.status === "rejected") {
    return { reservationId: reservationRef.id, status: "rejected", duplicate: true };
  }
  if (reservation.status !== "pendingRestaurantApproval") {
    throw new HttpsError(
      "failed-precondition",
      `Reservation is not pending restaurant approval (current status: ${reservation.status}).`,
    );
  }

  // Faz R.1D.1 §12 — read before any write below (hold release), never a
  // client-supplied order id.
  const preorderOrderId = reservation.preorderOrderId as string | null | undefined;
  const preorderOrderRef = preorderOrderId ? resolvePreorderOrderRef(db, reservationRef.id) : null;
  const preorderDoc = preorderOrderRef ? await tx.get(preorderOrderRef) : null;

  const activeHoldId = reservation.activeHoldId as string | null;
  if (activeHoldId) {
    const hold = readHoldRecord(await tx.get(db.collection("reservationHolds").doc(activeHoldId)));
    if (hold && hold.status === "active") {
      await releaseHold(tx, db, hold, now);
    }
  }

  // Faz R.1D.1 §12 — the linked preorder (if still pendingConfirmation) is
  // cancelled in this SAME transaction as the reservation's own reject
  // transition, so it can never later leak to KDS.
  if (preorderOrderRef && preorderDoc) {
    const patch = buildPreorderCancellationPatch(preorderDoc, now);
    if (patch) tx.set(preorderOrderRef, patch, { merge: true });
  }

  tx.set(
    reservationRef,
    {
      status: "rejected",
      reasonCode,
      reason,
      activeHoldId: null,
      respondedByStaffId: staffUid,
      updatedAt: now,
    },
    { merge: true },
  );

  writeReservationEvent(tx, db, {
    eventId: `${reservationRef.id}-rejected`,
    type: "reservationRejected",
    reservationId: reservationRef.id,
    organizationId: reservation.organizationId,
    restaurantId: reservation.restaurantId,
    branchId: reservation.branchId,
    recordedAt: now,
    extra: { reasonCode },
  });

  return { reservationId: reservationRef.id, status: "rejected", duplicate: false };
}

async function handleProposeChange(
  tx: Transaction,
  db: Firestore,
  reservationRef: DocumentReference,
  reservation: DocumentData,
  staffUid: string,
  now: Date,
  proposedTime: Date,
  proposedAreaId: string,
): Promise<HandlerResult> {
  // Faz R.1B §7 — the single-active-proposal invariant is enforced by this
  // status gate itself: only a Reservation still `pendingRestaurantApproval`
  // may receive a new proposal. A concurrent second proposeChange call
  // races on this same document's read-set; Firestore's transaction retry
  // forces the loser to re-read and see `changeProposed` already, failing
  // here — no separate proposal-scan needed.
  if (reservation.status !== "pendingRestaurantApproval") {
    throw new HttpsError(
      "failed-precondition",
      `Reservation is not pending restaurant approval (current status: ${reservation.status}).`,
    );
  }

  const scope = await resolveActiveReservationBranch(tx, db, {
    restaurantId: reservation.restaurantId,
    branchId: reservation.branchId,
  });
  if (scope.status !== "valid") {
    throw new HttpsError("failed-precondition", "This branch is no longer accepting reservations.");
  }
  const policy = scope.policy!;

  const area = await resolveReservationArea(tx, db, {
    branchId: reservation.branchId,
    areaId: proposedAreaId,
  });
  if (area.status === "notFound") {
    throw new HttpsError("not-found", "Reservation area not found.");
  }
  if (area.status === "invalid") {
    throw new HttpsError(
      "failed-precondition",
      "This reservation area is not currently accepting reservations.",
    );
  }

  const minimumTime = new Date(now.getTime() + MINIMUM_ADVANCE_MINUTES * 60_000);
  if (proposedTime.getTime() < minimumTime.getTime()) {
    throw new HttpsError(
      "failed-precondition",
      `proposedTime must be at least ${MINIMUM_ADVANCE_MINUTES} minutes from now.`,
    );
  }
  if (!isWithinBookingHorizon(now, proposedTime, policy.bookingHorizonDays, policy.timezone)) {
    throw new HttpsError(
      "failed-precondition",
      `proposedTime is beyond the ${policy.bookingHorizonDays}-day booking horizon.`,
    );
  }
  const slotMs = policy.slotIntervalMinutes * 60_000;
  if (proposedTime.getTime() % slotMs !== 0) {
    invalid(`proposedTime must align to a ${policy.slotIntervalMinutes}-minute slot boundary.`);
  }

  const endTime = new Date(proposedTime.getTime() + policy.reservationDurationMinutes * 60_000);
  const capacity = await checkAreaCapacity(db, tx, {
    branchId: reservation.branchId,
    areaId: proposedAreaId,
    areaCapacity: area.capacity!,
    start: proposedTime,
    end: endTime,
    slotIntervalMinutes: policy.slotIntervalMinutes,
    partySize: reservation.partySize,
  });
  if (!capacity.available) {
    throw new HttpsError("failed-precondition", "The proposed time/area is not available.");
  }

  // Faz R.1B §11 — release the OLD initial hold before creating the new
  // alternative-proposal hold, so a reservation never carries two
  // simultaneous active holds.
  const activeHoldId = reservation.activeHoldId as string | null;
  if (activeHoldId) {
    const oldHold = readHoldRecord(await tx.get(db.collection("reservationHolds").doc(activeHoldId)));
    if (oldHold && oldHold.status === "active") {
      await releaseHold(tx, db, oldHold, now);
    }
  }

  const proposalRef = db.collection("reservationChangeProposals").doc();
  const proposalId = proposalRef.id;
  const holdRef = db.collection("reservationHolds").doc();
  const holdId = holdRef.id;
  const customerResponseDeadlineAt = new Date(
    Math.min(now.getTime() + policy.proposalHoldMinutes * 60_000, proposedTime.getTime()),
  );

  tx.set(holdRef, {
    reservationId: reservationRef.id,
    organizationId: reservation.organizationId,
    branchId: reservation.branchId,
    areaId: proposedAreaId,
    bucketIds: capacity.buckets.map((b) => b.id),
    partySize: reservation.partySize,
    purpose: "alternativeProposal",
    status: "active",
    proposalId,
    expiresAt: customerResponseDeadlineAt,
    createdAt: now,
  });
  for (const bucket of capacity.buckets) {
    const bucketRef = db.collection("reservationSlotOccupancy").doc(bucket.id);
    tx.set(
      bucketRef,
      {
        branchId: reservation.branchId,
        areaId: proposedAreaId,
        slotStart: bucket.slotStart,
        capacity: area.capacity,
        confirmedPartySize: FieldValue.increment(0),
        heldPartySize: FieldValue.increment(reservation.partySize),
      },
      { merge: true },
    );
  }

  tx.set(proposalRef, {
    proposalId,
    reservationId: reservationRef.id,
    organizationId: reservation.organizationId,
    restaurantId: reservation.restaurantId,
    branchId: reservation.branchId,
    fromTime: reservation.requestedTime,
    fromAreaId: reservation.requestedAreaId,
    proposedTime,
    proposedAreaId,
    createdByStaffId: staffUid,
    createdAt: now,
    customerResponseDeadlineAt,
    status: "pendingCustomerResponse",
    holdId,
  });

  tx.set(
    reservationRef,
    {
      status: "changeProposed",
      activeProposalId: proposalId,
      activeHoldId: holdId,
      respondedByStaffId: staffUid,
      updatedAt: now,
      // Faz R.2 — denormalized snapshot of the active proposal, onto the
      // one document a customer can already read directly
      // (`reservations/{id}`, owner-read in firestore.rules).
      // `reservationChangeProposals` itself is deliberately still
      // org-staff-read-only (Faz R.1B's own scope decision, unchanged) —
      // rather than opening a second customer read path, the reservation
      // flow's change-proposal UX (before/after time+area) reads these
      // fields instead. Cleared to `null` wherever the proposal resolves
      // (accept/reject/expire) or a reservation is otherwise no longer
      // `changeProposed`, so they never linger stale.
      activeProposalProposedTime: proposedTime,
      activeProposalProposedAreaId: proposedAreaId,
      activeProposalCustomerResponseDeadlineAt: customerResponseDeadlineAt,
    },
    { merge: true },
  );

  writeReservationEvent(tx, db, {
    eventId: `${reservationRef.id}-changeProposed-${proposalId}`,
    type: "reservationChangeProposed",
    reservationId: reservationRef.id,
    organizationId: reservation.organizationId,
    restaurantId: reservation.restaurantId,
    branchId: reservation.branchId,
    recordedAt: now,
    extra: { proposalId },
  });

  return {
    reservationId: reservationRef.id,
    proposalId,
    status: "changeProposed",
    customerResponseDeadlineAt: customerResponseDeadlineAt.toISOString(),
    duplicate: false,
  };
}

export const respondToReservation = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const staffUid = request.auth.uid;

    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.reservationId !== "string" || data.reservationId.length === 0) {
      invalid("reservationId is required.");
    }
    const reservationId = data.reservationId as string;

    if (data.action !== "confirm" && data.action !== "reject" && data.action !== "proposeChange") {
      invalid("action must be 'confirm', 'reject', or 'proposeChange'.");
    }
    const action = data.action as "confirm" | "reject" | "proposeChange";

    const reasonCode = action === "reject" ? sanitizeReasonCode(data.reasonCode) : null;
    const reason = action === "reject" ? sanitizeOptionalReason(data.reason) : null;

    let proposedTime: Date | null = null;
    let proposedAreaId: string | null = null;
    if (action === "proposeChange") {
      if (typeof data.proposedTime !== "string") invalid("proposedTime is required.");
      proposedTime = new Date(data.proposedTime as string);
      if (Number.isNaN(proposedTime.getTime())) invalid("proposedTime is not a valid date.");
      if (!isMinuteAligned(proposedTime)) {
        invalid("proposedTime must be minute-aligned (zero seconds and milliseconds).");
      }
      if (typeof data.proposedAreaId !== "string" || data.proposedAreaId.length === 0) {
        invalid("proposedAreaId is required.");
      }
      proposedAreaId = data.proposedAreaId as string;
    }

    const db = getFirestore();
    const reservationRef = db.collection("reservations").doc(reservationId);

    // Faz R.1B.1 — the transaction's own return value IS the client
    // response; the corresponding reservationEvent (if any) is now written
    // by `writeReservationEvent` *inside* this same transaction, by each
    // handler, so it commits atomically with the state transition — never
    // as a separate step after `runTransaction` resolves.
    return db.runTransaction(async (tx) => {
      const reservationDoc = await tx.get(reservationRef);
      if (!reservationDoc.exists) {
        throw new HttpsError("not-found", "Reservation not found.");
      }
      const reservation = reservationDoc.data()!;

      // Cross-tenant staff must fail closed — checked only once the
      // reservation's real organizationId is known server-side, never
      // trusting any client-supplied organizationId/branchId.
      requireReservationManagerPermission(request, reservation.organizationId);

      const now = new Date();

      if (action === "confirm") {
        return handleConfirm(tx, db, reservationRef, reservation, staffUid, now);
      }
      if (action === "reject") {
        return handleReject(tx, db, reservationRef, reservation, staffUid, now, reasonCode!, reason);
      }
      return handleProposeChange(
        tx,
        db,
        reservationRef,
        reservation,
        staffUid,
        now,
        proposedTime!,
        proposedAreaId!,
      );
    });
  },
);
