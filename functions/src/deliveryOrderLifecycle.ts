import { HttpsError } from "firebase-functions/v2/https";
import {
  requireOrderId,
  sanitizeOptionalReasonMessage,
  requireRealCustomer,
  applyOrderLifecycleTransition,
  writeOrderStatusChangeAuditEvent,
  ORDER_REFUND_DISPOSITIONS,
  type TerminalActorType,
  type OrderRefundDisposition,
  type ApplyOrderLifecycleTransitionParams,
  type WriteOrderStatusChangeAuditEventParams,
} from "./orderLifecycle";

/**
 * `deliveryOrderLifecycle` — Boncuk Loyalty Program P5-B (2026-08-24).
 *
 * Shared building blocks for the five delivery lifecycle callables
 * (`respondToDeliveryOrder`/`advanceDeliveryOrderStatus`/
 * `cancelDeliveryOrder`/`cancelDeliveryOrderForStaff`/
 * `refundDeliveryOrder`) — mirrors `takeawayOrderLifecycle.ts`'s own shape
 * exactly. The write-phase helpers, `requireRealCustomer`,
 * `sanitizeOptionalReasonMessage`, `TerminalActorType`, the refund-
 * disposition enum, and the plain `orderId` requirement are imported
 * directly from the neutral `./orderLifecycle` module (not re-derived) —
 * same channel-agnostic implementation `takeawayOrderLifecycle.ts` itself
 * now re-exports. Only the reason-code closed enums and their sanitizers
 * below are genuinely delivery-specific, by the same convention (not
 * necessity) `takeawayOrderLifecycle.ts` already established — the actual
 * values are deliberately identical to takeaway's own sets (no new
 * business-rule vocabulary was requested for delivery), kept as delivery's
 * own enum only so each channel's reason codes can diverge independently in
 * the future without touching the other.
 */

export type { TerminalActorType };
export {
  requireOrderId as requireDeliveryOrderId,
  requireRealCustomer,
  sanitizeOptionalReasonMessage,
  applyOrderLifecycleTransition as applyDeliveryLifecycleTransition,
  writeOrderStatusChangeAuditEvent as writeDeliveryOrderStatusChangeAuditEvent,
};
export type ApplyDeliveryLifecycleTransitionParams = ApplyOrderLifecycleTransitionParams;
export type WriteDeliveryOrderStatusChangeAuditEventParams = WriteOrderStatusChangeAuditEventParams;

/**
 * Delivery's own name for the channel-generic `ORDER_REFUND_DISPOSITIONS`/
 * `OrderRefundDisposition` — see `./orderLifecycle`'s doc comment for the
 * full rationale. `manualExternalRefundConfirmed` is the only value this
 * phase can ever produce for delivery either — no payment-provider refund
 * executor exists for any channel (confirmed by audit, P4-D-A/P5-A).
 */
export const DELIVERY_REFUND_DISPOSITIONS = ORDER_REFUND_DISPOSITIONS;
export type DeliveryRefundDisposition = OrderRefundDisposition;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

export const DELIVERY_REJECTION_REASON_CODES = [
  "itemUnavailable",
  "kitchenUnavailable",
  "capacityUnavailable",
  "operationalIssue",
  "other",
] as const;
export type DeliveryRejectionReasonCode = (typeof DELIVERY_REJECTION_REASON_CODES)[number];

export function sanitizeDeliveryRejectionReasonCode(raw: unknown): DeliveryRejectionReasonCode {
  if (typeof raw !== "string" || !(DELIVERY_REJECTION_REASON_CODES as readonly string[]).includes(raw)) {
    invalid(`reasonCode must be one of: ${DELIVERY_REJECTION_REASON_CODES.join(", ")}.`);
  }
  return raw as DeliveryRejectionReasonCode;
}

export const DELIVERY_CANCELLATION_REASON_CODES = [
  "itemUnavailable",
  "kitchenUnavailable",
  "capacityUnavailable",
  "customerNoShow",
  "operationalIssue",
  "other",
] as const;
export type DeliveryCancellationReasonCode = (typeof DELIVERY_CANCELLATION_REASON_CODES)[number];

export function sanitizeDeliveryCancellationReasonCode(raw: unknown): DeliveryCancellationReasonCode {
  if (
    typeof raw !== "string" ||
    !(DELIVERY_CANCELLATION_REASON_CODES as readonly string[]).includes(raw)
  ) {
    invalid(`reasonCode must be one of: ${DELIVERY_CANCELLATION_REASON_CODES.join(", ")}.`);
  }
  return raw as DeliveryCancellationReasonCode;
}

export const DELIVERY_REFUND_REASON_CODES = [
  "qualityIssue",
  "wrongItem",
  "missingItem",
  "customerComplaint",
  "operationalError",
  "other",
] as const;
export type DeliveryRefundReasonCode = (typeof DELIVERY_REFUND_REASON_CODES)[number];

export function sanitizeDeliveryRefundReasonCode(raw: unknown): DeliveryRefundReasonCode {
  if (typeof raw !== "string" || !(DELIVERY_REFUND_REASON_CODES as readonly string[]).includes(raw)) {
    invalid(`reasonCode must be one of: ${DELIVERY_REFUND_REASON_CODES.join(", ")}.`);
  }
  return raw as DeliveryRefundReasonCode;
}
