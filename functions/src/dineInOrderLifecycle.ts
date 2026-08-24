import { HttpsError } from "firebase-functions/v2/https";
import {
  requireOrderId,
  sanitizeOptionalReasonMessage,
  applyOrderLifecycleTransition,
  writeOrderStatusChangeAuditEvent,
  ORDER_REFUND_DISPOSITIONS,
  type TerminalActorType,
  type OrderRefundDisposition,
} from "./orderLifecycle";

/**
 * `dineInOrderLifecycle` — Boncuk Loyalty Program P7-D.1 (2026-08-24).
 *
 * The dine-in-channel thin alias layer, mirroring `takeawayOrderLifecycle
 * .ts`/`deliveryOrderLifecycle.ts` exactly: every actually-generic piece
 * lives in `./orderLifecycle`, this file only adds the genuinely dine-in-
 * specific closed reason-code enums and their sanitizers.
 */

export type { TerminalActorType };
export {
  applyOrderLifecycleTransition as applyDineInLifecycleTransition,
  writeOrderStatusChangeAuditEvent as writeDineInOrderStatusChangeAuditEvent,
  sanitizeOptionalReasonMessage,
};

export function requireDineInOrderId(raw: unknown): string {
  return requireOrderId(raw);
}

export const DINE_IN_REJECTION_REASON_CODES = [
  "itemUnavailable",
  "kitchenUnavailable",
  "capacityUnavailable",
  "operationalIssue",
  "other",
] as const;
export type DineInRejectionReasonCode = (typeof DINE_IN_REJECTION_REASON_CODES)[number];

export const DINE_IN_CANCELLATION_REASON_CODES = [
  "itemUnavailable",
  "kitchenUnavailable",
  "capacityUnavailable",
  "guestLeft",
  "operationalIssue",
  "other",
] as const;
export type DineInCancellationReasonCode = (typeof DINE_IN_CANCELLATION_REASON_CODES)[number];

export const DINE_IN_REFUND_REASON_CODES = [
  "qualityIssue",
  "wrongItem",
  "missingItem",
  "customerComplaint",
  "operationalError",
  "other",
] as const;
export type DineInRefundReasonCode = (typeof DINE_IN_REFUND_REASON_CODES)[number];

export const DINE_IN_REFUND_DISPOSITIONS = ORDER_REFUND_DISPOSITIONS;
export type DineInRefundDisposition = OrderRefundDisposition;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

export function sanitizeDineInRejectionReasonCode(raw: unknown): DineInRejectionReasonCode {
  if (typeof raw !== "string" || !(DINE_IN_REJECTION_REASON_CODES as readonly string[]).includes(raw)) {
    invalid(`reasonCode must be one of: ${DINE_IN_REJECTION_REASON_CODES.join(", ")}.`);
  }
  return raw as DineInRejectionReasonCode;
}

export function sanitizeDineInCancellationReasonCode(raw: unknown): DineInCancellationReasonCode {
  if (typeof raw !== "string" || !(DINE_IN_CANCELLATION_REASON_CODES as readonly string[]).includes(raw)) {
    invalid(`reasonCode must be one of: ${DINE_IN_CANCELLATION_REASON_CODES.join(", ")}.`);
  }
  return raw as DineInCancellationReasonCode;
}

export function sanitizeDineInRefundReasonCode(raw: unknown): DineInRefundReasonCode {
  if (typeof raw !== "string" || !(DINE_IN_REFUND_REASON_CODES as readonly string[]).includes(raw)) {
    invalid(`reasonCode must be one of: ${DINE_IN_REFUND_REASON_CODES.join(", ")}.`);
  }
  return raw as DineInRefundReasonCode;
}
