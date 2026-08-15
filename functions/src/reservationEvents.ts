import type { Firestore, Transaction } from "firebase-admin/firestore";

/**
 * Reservation outbox events — Faz R.1B §17, hardened Faz R.1B.1 REQUIRED
 * fix #2. **Faz R.1B's original design wrote this record with `db
 * .collection(...).doc(id).create()` *after* `db.runTransaction()` had
 * already resolved** — reasoned at the time as mirroring
 * "notification delivery must never be part of transaction correctness."
 * That reasoning conflated two different things: delivery (sending a push/
 * SMS/email) legitimately happens outside any transaction and asynchronously;
 * but the outbox *record*'s existence is the one thing a future consumer
 * depends on, and writing it after commit reopened exactly the gap an
 * outbox pattern exists to close — a process crash or network failure
 * between the state-transition commit and the event write would silently
 * lose the event forever, with the Reservation itself already showing
 * `confirmed`/`rejected`/etc. and no way to tell anything was missed.
 *
 * **Fix**: `writeReservationEvent` takes a `Transaction` and calls `tx.set`
 * — the event document commits atomically with the state transition that
 * produced it, in the exact same transaction, or neither does. Every call
 * site (`respondToReservation.ts`, `respondToProposedChange.ts`,
 * `reservationSweep.ts`) now writes its event as one more `tx.set` inside
 * the mutating transaction, not as a separate step afterward.
 *
 * **`.set()`, not `.create()`, deliberately.** `onOrderCompleted.ts`'s own
 * outbox precedent uses `.create()` (fails on an existing doc) because it's
 * a Firestore *trigger*, independently re-invoked "at least once" by the
 * platform for the same underlying change — `.create()` is how it tells a
 * second invocation apart from a genuine duplicate. This module has no such
 * retrigger source: every call site already gates on the *business*
 * precondition first (Faz R.1B's own idempotency design — confirm/reject/
 * accept/reject-proposal all re-check the current authoritative status
 * inside the transaction and return early if the transition already
 * happened; the sweeps re-query for documents still in the due state, so an
 * already-resolved one is never picked up again). That gate is what makes a
 * retried transition a safe no-op — the event-writing code path is only
 * ever reached once per real business outcome. `.set()` on the same
 * deterministic id is a deliberately *cheaper* safety net on top of that:
 * if the gate were ever wrong, `.set()` degrades to "overwrite the same
 * document" (still exactly one `reservationEvents` doc for that outcome),
 * whereas `.create()` would instead abort the whole surrounding
 * transaction — including the state transition it's supposed to be atomic
 * with — on a condition that isn't really an error here.
 */
export type ReservationEventType =
  | "reservationConfirmed"
  | "reservationRejected"
  | "reservationChangeProposed"
  | "reservationChangeAccepted"
  | "reservationChangeRejected"
  | "reservationChangeExpired"
  | "reservationResponseTimedOut"
  // Faz R.3B §17 — terminal lifecycle events.
  | "reservationCancelled"
  | "reservationCompleted"
  | "reservationNoShow";

/**
 * Faz R.3B §17 — who performed the action, for `reservationCancelled`/
 * `reservationCompleted`/`reservationNoShow` (every other event type is
 * always staff-only already, per its own callable). Deliberately minimal:
 * only the actor's *kind* and their own uid (never a role name, a
 * permission list, or any other custom-claims content) — "do not expose
 * sensitive claims."
 */
export interface ReservationEventActor {
  actorType: "customer" | "staff";
  actorId: string;
}

export function writeReservationEvent(
  tx: Transaction,
  db: Firestore,
  params: {
    eventId: string;
    type: ReservationEventType;
    reservationId: string;
    organizationId: string;
    restaurantId: string;
    branchId: string;
    recordedAt: Date;
    actor?: ReservationEventActor;
    extra?: Record<string, unknown>;
  },
): void {
  tx.set(db.collection("reservationEvents").doc(params.eventId), {
    type: params.type,
    reservationId: params.reservationId,
    organizationId: params.organizationId,
    restaurantId: params.restaurantId,
    branchId: params.branchId,
    recordedAt: params.recordedAt.toISOString(),
    delivered: false,
    ...(params.actor ? { actorType: params.actor.actorType, actorId: params.actor.actorId } : {}),
    ...(params.extra ?? {}),
  });
}
