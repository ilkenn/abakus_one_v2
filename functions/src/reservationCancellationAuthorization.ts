import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { requireStaffPermission } from "./staffAuthorization";

/**
 * Faz R.3B §2/§3/§4 — `cancelReservation` is a single callable serving both
 * customer and staff cancellation, but WHO is cancelling is always resolved
 * server-side, never accepted as a client-supplied `actorType`.
 */

export type ReservationCancellationActorType = "customer" | "staff";

export interface ReservationCancellationActor {
  actorType: ReservationCancellationActorType;
  actorId: string;
}

function toDate(value: unknown): Date {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") {
    return (value as { toDate: () => Date }).toDate();
  }
  return new Date(value as string);
}

/**
 * Canonical actor resolution: a caller whose own uid equals
 * `reservation.customerId` is always resolved as CUSTOMER — checked first,
 * deterministically, even for the edge case of a uid that is *also* staff
 * for the same organization (rare, but possible: a staff member who
 * separately booked a table for themselves). Real-phone-auth is required
 * for the customer path, exactly mirroring `submitReservation.ts`'s own
 * `isRealCustomer` gate. Anyone else must independently hold
 * `manageReservations` for the reservation's own organization to resolve
 * as STAFF — cross-tenant/unrelated/anonymous callers fail closed with
 * `permission-denied` via `requireStaffPermission`'s own existing
 * behavior, with zero special-casing needed for "anonymous" specifically:
 * an anonymous uid can never equal `reservation.customerId` in the first
 * place (`submitReservation` itself requires phone-auth to create one), so
 * it always falls through to the staff-permission check, which then
 * denies it exactly like any other non-staff caller.
 */
export function resolveReservationCancellationActor(
  request: CallableRequest,
  reservation: FirebaseFirestore.DocumentData,
): ReservationCancellationActor {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const uid = request.auth.uid;

  if (reservation.customerId === uid) {
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Cancelling a reservation requires a phone-verified identity.",
      );
    }
    return { actorType: "customer", actorId: uid };
  }

  requireStaffPermission(request, reservation.organizationId as string, "manageReservations");
  return { actorType: "staff", actorId: uid };
}

export interface CustomerCancellationCutoffCheck {
  anchorTime: Date;
  cutoffReached: boolean;
}

/**
 * Faz R.3B §5 — the customer self-cancellation cutoff anchor + eligibility,
 * computed entirely against server time (`now`), never the client's clock.
 * `ReservationPolicy.customerCancellationCutoffMinutes` (already part of
 * the canonical policy shape since Faz R.1A, simply unconsumed until this
 * phase) is the sole cutoff-duration authority.
 *
 * Anchor resolution:
 * - `confirmed` — `confirmedTime` (the actual bound seating time).
 * - `changeProposed` with an active proposal snapshot present — the
 *   *earlier* of `requestedTime`/the proposal's `proposedTime` (Faz R.3B
 *   §5's own explicit "fail-safe cutoff" instruction: erring toward the
 *   sooner of the two upcoming times a customer might reasonably still be
 *   expected at, rather than the later one).
 * - Everything else (`pendingRestaurantApproval`, or `changeProposed`
 *   defensively missing its proposal snapshot) — `requestedTime`.
 */
export function computeCustomerCancellationCutoff(
  reservation: FirebaseFirestore.DocumentData,
  cutoffMinutes: number,
  now: Date,
): CustomerCancellationCutoffCheck {
  let anchorTime: Date;
  if (reservation.status === "confirmed" && reservation.confirmedTime) {
    anchorTime = toDate(reservation.confirmedTime);
  } else if (reservation.status === "changeProposed" && reservation.activeProposalProposedTime) {
    const requestedTime = toDate(reservation.requestedTime);
    const proposedTime = toDate(reservation.activeProposalProposedTime);
    anchorTime = requestedTime.getTime() <= proposedTime.getTime() ? requestedTime : proposedTime;
  } else {
    anchorTime = toDate(reservation.requestedTime);
  }

  const cutoffAt = new Date(anchorTime.getTime() - cutoffMinutes * 60_000);
  return { anchorTime, cutoffReached: now.getTime() >= cutoffAt.getTime() };
}
