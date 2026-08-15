import type { Firestore, Transaction } from "firebase-admin/firestore";

/**
 * Reservation branch policy — Faz R.1A implementation of the
 * `docs/decisions.md` ADR-027 Faz R.0.1/R.0.2/R.0.3/R.0.7 design.
 *
 * `minimumAdvanceMinutes` is deliberately **not** a field here — Faz R.0.2/
 * R.0.7 locked it as a platform-wide constant (`MINIMUM_ADVANCE_MINUTES`
 * below), never branch-configurable, and Faz R.0.7 explicitly removed the
 * one speculative policy field an earlier draft had added
 * (`preorderPreparationLeadMinutes`) — this interface intentionally carries
 * only the eight fields Faz R.0.7 §6 named as the final, locked policy
 * shape.
 */
export interface ReservationPolicy {
  /** Faz R.0.6/R.0.7 §9 — the sole authority for "does this branch accept reservation requests at all." Never `supportedOrderChannelIds` (that's the wrong axis — a table-only booking never produces an Order, let alone a `reservationPreorder`-channel one). */
  enabled: boolean;
  bookingHorizonDays: number;
  slotIntervalMinutes: number;
  reservationDurationMinutes: number;
  maxPartySize: number;
  customerCancellationCutoffMinutes: number;
  restaurantResponseTimeoutMinutes: number;
  proposalHoldMinutes: number;
  timezone: string;
}

/**
 * USER-LOCKED (Faz R.0.2, re-confirmed R.0.7) — a platform-wide constant,
 * never branch-configurable. Mirrors `PICKUP_MINIMUM_LEAD_MINUTES`'s own
 * "const, not a policy field" shape (`submitTakeawayOrder.ts`).
 */
export const MINIMUM_ADVANCE_MINUTES = 30;

/**
 * USER-LOCKED (Faz R.1D.1) — a platform-wide constant, never branch-
 * configurable, mirroring `MINIMUM_ADVANCE_MINUTES`'s own precedent above.
 * The lead time before a confirmed reservation's `confirmedTime` at which
 * its optional preorder (`reservationPreorder.ts`) becomes KDS-eligible:
 * `kitchenReleaseAt = confirmedTime - PREORDER_KITCHEN_RELEASE_LEAD_MINUTES`.
 * If fewer than this many minutes remain at the moment of confirmation, the
 * preorder is immediately `confirmed` instead of waiting on a future
 * release (no scheduled release poller exists yet — Faz R.1D.2's job).
 */
export const PREORDER_KITCHEN_RELEASE_LEAD_MINUTES = 60;

/**
 * Loads `reservationPolicies/{branchId}` via `tx.get()` — Faz R.1A.1
 * (`docs/decisions.md` ADR-027 Faz R.1A.1 REQUIRED fix #1). An earlier
 * draft used a plain, non-transactional read here on the reasoning that
 * config data "isn't itself mutated by this request" — that reasoning was
 * wrong: `enabled`/`maxPartySize`/etc. **are** authoritative inputs to the
 * accept/reject decision this transaction makes, and a plain read doesn't
 * participate in Firestore's optimistic-concurrency conflict detection. If
 * this document is modified by another write while this transaction is
 * in flight, a plain read would silently commit against stale data instead
 * of Firestore forcing the automatic retry a `tx.get()` read gets for
 * free. Returns `null` for a branch with no policy document at all
 * (treated as "reservations not enabled" by the caller, never silently
 * defaulted to some enabled shape).
 */
export async function loadReservationPolicy(
  tx: Transaction,
  db: Firestore,
  branchId: string,
): Promise<ReservationPolicy | null> {
  const doc = await tx.get(db.collection("reservationPolicies").doc(branchId));
  if (!doc.exists) return null;
  const data = doc.data()!;
  return {
    enabled: data.enabled === true,
    bookingHorizonDays: Number(data.bookingHorizonDays),
    slotIntervalMinutes: Number(data.slotIntervalMinutes),
    reservationDurationMinutes: Number(data.reservationDurationMinutes),
    maxPartySize: Number(data.maxPartySize),
    customerCancellationCutoffMinutes: Number(data.customerCancellationCutoffMinutes),
    restaurantResponseTimeoutMinutes: Number(data.restaurantResponseTimeoutMinutes),
    proposalHoldMinutes: Number(data.proposalHoldMinutes),
    timezone: typeof data.timezone === "string" ? data.timezone : "UTC",
  };
}
