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
 * `takeawayOrderLifecycle` — Boncuk Loyalty Program P4-C-C-B (2026-08-22),
 * refactored P5-B (2026-08-24).
 *
 * Shared building blocks for the five takeaway lifecycle callables
 * (`respondToTakeawayOrder`/`advanceTakeawayOrderStatus`/
 * `cancelTakeawayOrder`/`cancelTakeawayOrderForStaff`/`refundTakeawayOrder`,
 * the last added P4-D-B, 2026-08-22) — closed reason-code enums, input
 * sanitizers, and the two write-phase helpers every callable shares.
 *
 * **P5-B: the actually-generic pieces of this file (the write-phase
 * helpers, `requireRealCustomer`, `sanitizeOptionalReasonMessage`,
 * `TerminalActorType`, the refund-disposition enum, and the plain
 * `orderId` requirement) moved to the neutral `./orderLifecycle` module so
 * `deliveryOrderLifecycle.ts` could reuse them — this file now re-exports
 * every one of them under its ORIGINAL name as a thin alias, so nothing
 * below changed behavior and none of the five takeaway callable files
 * needed to change their own imports.** Only the genuinely takeaway-specific
 * closed reason-code enums and their sanitizers are still implemented here.
 *
 * **Rejection vs. cancellation reason codes are deliberately two separate
 * closed enums, not one shared list** (P4-C-C-A §5/§6) — checked against
 * existing project terminology before finalizing: `reservation`'s own
 * `cancelReservation.ts` `reasonCode` is an UNVALIDATED free-form string
 * (only length-capped), not a closed enum — there was no existing closed
 * enum to reuse here, confirming this is genuinely new ground, not a
 * duplicate of something that already exists. `customerNoShow` is added to
 * the CANCELLATION set only (not rejection) — a real, common restaurant
 * scenario the task's own example list didn't include: a confirmed order
 * whose customer never arrived to collect it. Rejection happens before any
 * commitment (no meaningful "no-show" concept applies yet).
 */

export type { TerminalActorType };
export {
  requireRealCustomer,
  applyOrderLifecycleTransition as applyTakeawayLifecycleTransition,
  writeOrderStatusChangeAuditEvent as writeTakeawayOrderStatusChangeAuditEvent,
  sanitizeOptionalReasonMessage,
};
export type ApplyTakeawayLifecycleTransitionParams = ApplyOrderLifecycleTransitionParams;
export type WriteTakeawayOrderStatusChangeAuditEventParams = WriteOrderStatusChangeAuditEventParams;

export function requireTakeawayOrderId(raw: unknown): string {
  return requireOrderId(raw);
}

export const TAKEAWAY_REJECTION_REASON_CODES = [
  "itemUnavailable",
  "kitchenUnavailable",
  "capacityUnavailable",
  "operationalIssue",
  "other",
] as const;
export type TakeawayRejectionReasonCode = (typeof TAKEAWAY_REJECTION_REASON_CODES)[number];

export const TAKEAWAY_CANCELLATION_REASON_CODES = [
  "itemUnavailable",
  "kitchenUnavailable",
  "capacityUnavailable",
  "customerNoShow",
  "operationalIssue",
  "other",
] as const;
export type TakeawayCancellationReasonCode = (typeof TAKEAWAY_CANCELLATION_REASON_CODES)[number];

/**
 * Boncuk Loyalty P4-D-B (2026-08-22) — a refund happens strictly AFTER
 * `completed`, a semantically distinct trigger set from rejection
 * (pre-acceptance) or cancellation (post-acceptance, pre-fulfillment) —
 * deliberately its own closed enum, never sharing either prior set, even
 * though `operationalError` here and `operationalIssue` above look
 * similar: rejection/cancellation are about ABILITY to fulfill an order
 * that hasn't happened yet; a refund's `operationalError` is about
 * something that went wrong in an order that already DID happen.
 */
export const TAKEAWAY_REFUND_REASON_CODES = [
  "qualityIssue",
  "wrongItem",
  "missingItem",
  "customerComplaint",
  "operationalError",
  "other",
] as const;
export type TakeawayRefundReasonCode = (typeof TAKEAWAY_REFUND_REASON_CODES)[number];

/**
 * Boncuk Loyalty P4-D-B — takeaway's own name for the channel-generic
 * `ORDER_REFUND_DISPOSITIONS`/`OrderRefundDisposition` (moved to
 * `./orderLifecycle` P5-B — see that module's doc comment for the full
 * rationale). Re-exported under the original name so
 * `refundTakeawayOrder.ts` and any future takeaway code need no changes.
 */
export const TAKEAWAY_REFUND_DISPOSITIONS = ORDER_REFUND_DISPOSITIONS;
export type TakeawayRefundDisposition = OrderRefundDisposition;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

export function sanitizeRejectionReasonCode(raw: unknown): TakeawayRejectionReasonCode {
  if (typeof raw !== "string" || !(TAKEAWAY_REJECTION_REASON_CODES as readonly string[]).includes(raw)) {
    invalid(`reasonCode must be one of: ${TAKEAWAY_REJECTION_REASON_CODES.join(", ")}.`);
  }
  return raw as TakeawayRejectionReasonCode;
}

export function sanitizeCancellationReasonCode(raw: unknown): TakeawayCancellationReasonCode {
  if (typeof raw !== "string" || !(TAKEAWAY_CANCELLATION_REASON_CODES as readonly string[]).includes(raw)) {
    invalid(`reasonCode must be one of: ${TAKEAWAY_CANCELLATION_REASON_CODES.join(", ")}.`);
  }
  return raw as TakeawayCancellationReasonCode;
}

export function sanitizeRefundReasonCode(raw: unknown): TakeawayRefundReasonCode {
  if (typeof raw !== "string" || !(TAKEAWAY_REFUND_REASON_CODES as readonly string[]).includes(raw)) {
    invalid(`reasonCode must be one of: ${TAKEAWAY_REFUND_REASON_CODES.join(", ")}.`);
  }
  return raw as TakeawayRefundReasonCode;
}
