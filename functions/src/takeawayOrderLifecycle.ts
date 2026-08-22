import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import type { Firestore, Transaction, DocumentData, DocumentReference } from "firebase-admin/firestore";
import type { OrderStatus } from "./orderStatus";

/**
 * `takeawayOrderLifecycle` — Boncuk Loyalty Program P4-C-C-B (2026-08-22).
 *
 * Shared building blocks for the four new takeaway lifecycle callables
 * (`respondToTakeawayOrder`/`advanceTakeawayOrderStatus`/
 * `cancelTakeawayOrder`/`cancelTakeawayOrderForStaff`) — closed reason-code
 * enums, input sanitizers, and the two write-phase helpers every callable
 * shares (`applyTakeawayLifecycleTransition`/
 * `writeTakeawayOrderStatusChangeAuditEvent`). No Firestore reads happen
 * here — every function in this file is either pure validation or a
 * write-phase helper the CALLER invokes only after its own transaction has
 * already validated the current status (the actual idempotency gate lives
 * in each callable, not here).
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
 * Closed, customer-safe actor category — the ONLY actor field ever written
 * to the customer-readable order document (`terminalActorType`). Never a
 * raw uid — see `applyTakeawayLifecycleTransition`'s own doc comment for
 * why `terminalActorUid` must never exist on that document at all.
 */
export type TerminalActorType = "customer" | "staff" | "system";

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

export function requireTakeawayOrderId(raw: unknown): string {
  if (typeof raw !== "string" || raw.length === 0) {
    invalid("orderId is required.");
  }
  return raw as string;
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

const MAX_REASON_MESSAGE_LENGTH = 500;

/** `reasonMessage` is an INTERNAL staff note only — never written anywhere the customer can read it (see `writeTakeawayOrderStatusChangeAuditEvent`). */
export function sanitizeOptionalReasonMessage(raw: unknown): string | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "string") invalid("reasonMessage must be a string.");
  const trimmed = (raw as string).trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > MAX_REASON_MESSAGE_LENGTH) invalid("reasonMessage is too long.");
  return trimmed;
}

/** Real, phone-verified customer check — the same inline pattern used at 15+ call sites across this codebase (no shared helper exists repo-wide; introducing one is out of this phase's scope). */
export function requireRealCustomer(request: CallableRequest): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
  if (!isRealCustomer) {
    throw new HttpsError(
      "permission-denied",
      "This action requires a real, phone-verified customer identity.",
    );
  }
  return request.auth.uid;
}

/** The `timestamps` slots `buildOrderDocument` (submitTakeawayOrder.ts) already provisions (always `null` until a real writer populates one) — `rejected` has no dedicated slot; `terminalAt` (set by `applyTakeawayLifecycleTransition` for every terminal transition) already covers it, so no new slot is added for it. */
const TIMESTAMP_SLOT_FOR_STATUS: Partial<Record<OrderStatus, string>> = {
  confirmed: "confirmed",
  preparing: "preparing",
  ready: "ready",
  completed: "completed",
  cancelled: "cancelled",
};

export interface ApplyTakeawayLifecycleTransitionParams {
  tx: Transaction;
  orderRef: DocumentReference<DocumentData>;
  orderId: string;
  order: DocumentData;
  fromStatus: OrderStatus;
  toStatus: OrderStatus;
  actorType: TerminalActorType;
  now: Timestamp;
  /** Present only for a terminal (`rejected`/`cancelled`) transition; ignored otherwise. */
  terminalReasonCode?: string | null;
}

/**
 * The WRITE phase of one canonical takeaway status transition — appends
 * exactly one `statusHistory` entry, populates the matching existing
 * `timestamps` slot (never a new, duplicate concept — P4-C-C-B §8), bumps
 * `version`, and — only for a terminal transition — stamps the
 * customer-safe terminal fields (`terminalReasonCode`/`terminalActorType`/
 * `terminalAt`).
 *
 * **`terminalActorUid` is deliberately never written here, on purpose, by
 * design — this document is customer-readable.** A staff member's uid is
 * internal operational data; it belongs only in `auditEvents` (via
 * `writeTakeawayOrderStatusChangeAuditEvent`), never on a document the
 * order's own customer can read.
 *
 * Callers are responsible for their OWN current-status precondition check
 * BEFORE calling this — this function performs no read and no idempotency
 * check of its own; it assumes the caller has already established that
 * `fromStatus -> toStatus` is a genuinely new transition for this order.
 */
export function applyTakeawayLifecycleTransition(
  params: ApplyTakeawayLifecycleTransitionParams,
): void {
  const { tx, orderRef, orderId, order, fromStatus, toStatus, actorType, now, terminalReasonCode } =
    params;
  const nowIso = now.toDate().toISOString();
  const isTerminal = toStatus === "rejected" || toStatus === "cancelled";

  const statusHistory = Array.isArray(order.statusHistory) ? order.statusHistory : [];
  const transitionId = `${orderId}-transition-${toStatus}`;

  const update: Record<string, unknown> = {
    status: toStatus,
    statusHistory: [
      ...statusHistory,
      {
        id: transitionId,
        type: "statusChange",
        description: `Status changed from ${fromStatus} to ${toStatus}`,
        actor: actorType,
        timestamp: nowIso,
        previousValue: fromStatus,
        newValue: toStatus,
      },
    ],
  };

  const timestampSlot = TIMESTAMP_SLOT_FOR_STATUS[toStatus];
  if (timestampSlot) {
    update[`timestamps.${timestampSlot}`] = nowIso;
  }

  if (isTerminal) {
    update.terminalReasonCode = terminalReasonCode ?? null;
    update.terminalActorType = actorType;
    update.terminalAt = nowIso;
  }

  tx.update(orderRef, update);
}

export interface WriteTakeawayOrderStatusChangeAuditEventParams {
  tx: Transaction;
  db: Firestore;
  orderId: string;
  organizationId: string;
  branchId: string;
  fromStatus: OrderStatus;
  toStatus: OrderStatus;
  actorType: TerminalActorType;
  /** Internal-only — never written to the order document, only here. */
  actorUid: string | null;
  actorRoles?: readonly string[] | null;
  reasonCode?: string | null;
  /** Internal staff note only — never customer-readable. */
  reasonMessage?: string | null;
  now: Timestamp;
}

/**
 * Extends `auditEvents`' existing `type: "order.statusChanged"` shape
 * (already written by `onOrderCreated.ts`/`reservationPreorder.ts`,
 * confirmed by direct inspection before writing this — no parallel audit
 * collection introduced). `actor` is preserved as the existing coarse
 * string field (`"system"`/`"staff"`/`"customer"`, matching the shape
 * every prior writer already used); the new fields (`branchId`,
 * `actorType`, `actorUid`, `actorRoles`, `reasonCode`, `reasonMessage`) are
 * purely additive, mirroring this codebase's own established
 * backward-compatible-additive-field convention.
 *
 * Deterministic document id (`${orderId}-status-${fromStatus}-${toStatus}`)
 * — a given order can only ever make a specific `from -> to` transition
 * once (the state machine has no cycles), so this id can never legitimately
 * collide. `tx.set()`, not `tx.create()`: the true idempotency gate is each
 * callable's own current-status precondition check (re-verified inside the
 * SAME transaction as this write), which already guarantees this function
 * is only ever reached once per real transition — `tx.create()`'s
 * mid-transaction ALREADY_EXISTS failure mode cannot be gracefully caught
 * the way a standalone `.create()` (e.g. `onOrderCompleted.ts`'s own
 * outbox write) can be, so it is not used here.
 */
export function writeTakeawayOrderStatusChangeAuditEvent(
  params: WriteTakeawayOrderStatusChangeAuditEventParams,
): void {
  const {
    tx,
    db,
    orderId,
    organizationId,
    branchId,
    fromStatus,
    toStatus,
    actorType,
    actorUid,
    actorRoles,
    reasonCode,
    reasonMessage,
    now,
  } = params;
  const eventId = `${orderId}-status-${fromStatus}-${toStatus}`;
  tx.set(db.collection("auditEvents").doc(eventId), {
    organizationId,
    branchId,
    type: "order.statusChanged",
    orderId,
    previousValue: fromStatus,
    newValue: toStatus,
    actor: actorType,
    actorType,
    actorUid: actorUid ?? null,
    actorRoles: actorRoles ?? null,
    reasonCode: reasonCode ?? null,
    reasonMessage: reasonMessage ?? null,
    timestamp: now.toDate().toISOString(),
  });
}
