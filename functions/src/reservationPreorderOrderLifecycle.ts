import { HttpsError } from "firebase-functions/v2/https";
import {
  requireOrderId,
  sanitizeOptionalReasonMessage,
  applyOrderLifecycleTransition,
  writeOrderStatusChangeAuditEvent,
  ORDER_REFUND_DISPOSITIONS,
  type TerminalActorType,
  type OrderRefundDisposition,
  type ApplyOrderLifecycleTransitionParams,
  type WriteOrderStatusChangeAuditEventParams,
} from "./orderLifecycle";

/**
 * `reservationPreorderOrderLifecycle` — Boncuk Loyalty Program P6-B
 * (2026-08-24).
 *
 * Shared building blocks for the POST-RELEASE-TO-KITCHEN lifecycle of a
 * `reservationPreorder`-channel order — `respondToDeliveryOrder`/
 * `deliveryOrderLifecycle.ts`'s own P5-B pattern, applied to the third
 * channel. Mirrors `deliveryOrderLifecycle.ts` exactly: the write-phase
 * helpers, `TerminalActorType`, and the refund-disposition enum are
 * imported directly from the neutral `./orderLifecycle` module (not
 * re-derived) — the same channel-agnostic implementation
 * `takeawayOrderLifecycle.ts`/`deliveryOrderLifecycle.ts` themselves
 * re-export. Only the reason-code closed enums and their sanitizers below
 * are genuinely reservation-preorder-specific, by the same convention (not
 * necessity) the other two channels already established.
 *
 * **Deliberately NOT used for the PRE-release (`pendingConfirmation`)
 * transitions** — those remain exactly as `reservationPreorder.ts`'s own
 * `buildPreorderConfirmationPatch`/`buildPreorderCancellationPatch` already
 * implement them (P5-A/P6-A confirmed these work correctly and are
 * exercised by `respondToReservation.ts`/`cancelReservation.ts`/
 * `markReservationNoShow.ts`/`reservationSweep.ts` for the pre-release
 * paths) — this module exists ONLY for the new post-release
 * `confirmed → preparing → ready → served → completed` kitchen pipeline
 * and its own cancel/refund paths (P6-A's proven structural gap), never a
 * replacement for the pre-release mechanism.
 */

export type { TerminalActorType };
export {
  requireOrderId as requireReservationPreorderOrderId,
  sanitizeOptionalReasonMessage,
  applyOrderLifecycleTransition as applyReservationPreorderOrderLifecycleTransition,
  writeOrderStatusChangeAuditEvent as writeReservationPreorderOrderStatusChangeAuditEvent,
};
export type ApplyReservationPreorderOrderLifecycleTransitionParams = ApplyOrderLifecycleTransitionParams;
export type WriteReservationPreorderOrderStatusChangeAuditEventParams = WriteOrderStatusChangeAuditEventParams;

/**
 * Reservation preorder's own name for the channel-generic
 * `ORDER_REFUND_DISPOSITIONS`/`OrderRefundDisposition` — see
 * `./orderLifecycle`'s doc comment for the full rationale.
 * `manualExternalRefundConfirmed` is the only value this phase can ever
 * produce here either — no payment-provider refund executor exists for any
 * channel (confirmed by audit, P4-D-A/P5-A/P6-A), and a reservation
 * preorder additionally has no online-payment concept at all today
 * (pay-at-the-restaurant, confirmed by P6-A).
 */
export const RESERVATION_PREORDER_REFUND_DISPOSITIONS = ORDER_REFUND_DISPOSITIONS;
export type ReservationPreorderRefundDisposition = OrderRefundDisposition;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

/**
 * Staff post-release cancellation (P6-B §5) and the no-show-before-
 * fulfillment path (P6-B §7/§8, applied from `markReservationNoShow.ts`
 * directly) share this one closed enum — deliberately identical VALUES to
 * takeaway's/delivery's own cancellation reason sets (no new business-rule
 * vocabulary was requested), kept as its own enum only so this channel can
 * diverge independently in the future.
 */
export const RESERVATION_PREORDER_CANCELLATION_REASON_CODES = [
  "itemUnavailable",
  "kitchenUnavailable",
  "capacityUnavailable",
  "customerNoShow",
  "operationalIssue",
  "other",
] as const;
export type ReservationPreorderCancellationReasonCode =
  (typeof RESERVATION_PREORDER_CANCELLATION_REASON_CODES)[number];

export function sanitizeReservationPreorderCancellationReasonCode(
  raw: unknown,
): ReservationPreorderCancellationReasonCode {
  if (
    typeof raw !== "string" ||
    !(RESERVATION_PREORDER_CANCELLATION_REASON_CODES as readonly string[]).includes(raw)
  ) {
    invalid(
      `reasonCode must be one of: ${RESERVATION_PREORDER_CANCELLATION_REASON_CODES.join(", ")}.`,
    );
  }
  return raw as ReservationPreorderCancellationReasonCode;
}

export const RESERVATION_PREORDER_REFUND_REASON_CODES = [
  "qualityIssue",
  "wrongItem",
  "missingItem",
  "customerComplaint",
  "operationalError",
  "other",
] as const;
export type ReservationPreorderRefundReasonCode = (typeof RESERVATION_PREORDER_REFUND_REASON_CODES)[number];

export function sanitizeReservationPreorderRefundReasonCode(
  raw: unknown,
): ReservationPreorderRefundReasonCode {
  if (
    typeof raw !== "string" ||
    !(RESERVATION_PREORDER_REFUND_REASON_CODES as readonly string[]).includes(raw)
  ) {
    invalid(`reasonCode must be one of: ${RESERVATION_PREORDER_REFUND_REASON_CODES.join(", ")}.`);
  }
  return raw as ReservationPreorderRefundReasonCode;
}
