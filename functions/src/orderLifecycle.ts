import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import type { Firestore, Transaction, DocumentData, DocumentReference } from "firebase-admin/firestore";
import type { OrderStatus } from "./orderStatus";

/**
 * `orderLifecycle` — Boncuk Loyalty Program P5-B (2026-08-24).
 *
 * Extracted from `takeawayOrderLifecycle.ts` (P4-C-C-B/P4-D-B) into its own
 * neutral, channel-agnostic module so `deliveryOrderLifecycle.ts` (P5-B) can
 * reuse the SAME write-phase helpers and generic validation rather than a
 * second, private copy. Every symbol below was already 100% channel-generic
 * in its original home despite the "takeaway"-named file it lived in — no
 * behavior changed in this move, only the location. **Byte-for-byte behavior
 * preserved for takeaway** — `takeawayOrderLifecycle.ts` now re-exports every
 * symbol below under its original name as a thin alias, so the five existing,
 * tested, committed takeaway callable files (`respondToTakeawayOrder`/
 * `advanceTakeawayOrderStatus`/`cancelTakeawayOrder`/
 * `cancelTakeawayOrderForStaff`/`refundTakeawayOrder`) require zero changes.
 *
 * The channel-specific closed reason-code enums (rejection/cancellation/
 * refund reason codes and their sanitizers) are deliberately NOT here — they
 * remain genuinely per-channel by convention, not necessity, and each
 * channel's own lifecycle file (`takeawayOrderLifecycle.ts`/
 * `deliveryOrderLifecycle.ts`) still declares its own.
 */

/**
 * Closed, customer-safe actor category — the ONLY actor field ever written
 * to the customer-readable order document (`terminalActorType`). Never a
 * raw uid — see `applyOrderLifecycleTransition`'s own doc comment for why
 * `terminalActorUid` must never exist on that document at all.
 */
export type TerminalActorType = "customer" | "staff" | "system";

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

export function requireOrderId(raw: unknown): string {
  if (typeof raw !== "string" || raw.length === 0) {
    invalid("orderId is required.");
  }
  return raw as string;
}

const MAX_REASON_MESSAGE_LENGTH = 500;

/** `reasonMessage` is an INTERNAL staff note only — never written anywhere the customer can read it (see `writeOrderStatusChangeAuditEvent`). */
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

/**
 * Boncuk Loyalty P5-B — deliberately separates the CANONICAL order refund
 * fact (`order.status == 'refunded'`, meaning the refund has actually been
 * completed/confirmed) from the PAYMENT-execution fact (`refundDisposition`,
 * meaning HOW the money was actually returned). Channel-generic: neither
 * takeaway nor delivery has a real payment-provider refund executor wired
 * (confirmed by audit, P4-D-A/P5-A) — `manualExternalRefundConfirmed` is the
 * ONLY value either channel can ever produce today; `providerRefundSucceeded`
 * is declared only so the type is forward-compatible, never written by any
 * code in this phase. There is deliberately NO `providerRefundPending`/
 * `providerRefundFailed` value — a pending or failed provider refund must
 * never cause `order.status` to become `refunded` in the first place.
 */
export const ORDER_REFUND_DISPOSITIONS = [
  "manualExternalRefundConfirmed",
  "providerRefundSucceeded",
] as const;
export type OrderRefundDisposition = (typeof ORDER_REFUND_DISPOSITIONS)[number];

/** The `timestamps` slots each channel's `buildOrderDocument`-equivalent already provisions (always `null` until a real writer populates one) — `rejected`/`refunded`/`outForDelivery` have no dedicated slot; `terminalAt` (set by `applyOrderLifecycleTransition` for every terminal transition) already covers the two terminal ones, and `outForDelivery`'s own `statusHistory` entry is its only timestamp record (a pre-existing data-model gap shared with `rejected`, not something this phase needs to fix). */
const TIMESTAMP_SLOT_FOR_STATUS: Partial<Record<OrderStatus, string>> = {
  confirmed: "confirmed",
  preparing: "preparing",
  ready: "ready",
  completed: "completed",
  cancelled: "cancelled",
};

export interface ApplyOrderLifecycleTransitionParams {
  tx: Transaction;
  orderRef: DocumentReference<DocumentData>;
  orderId: string;
  order: DocumentData;
  fromStatus: OrderStatus;
  toStatus: OrderStatus;
  actorType: TerminalActorType;
  now: Timestamp;
  /** Present only for a terminal (`rejected`/`cancelled`/`refunded`) transition; ignored otherwise. */
  terminalReasonCode?: string | null;
  /** Present ONLY for a `refunded` transition — see `ORDER_REFUND_DISPOSITIONS`'s own doc comment. Always passed explicitly by the caller, never defaulted here. */
  refundDisposition?: OrderRefundDisposition | null;
}

/**
 * The WRITE phase of one canonical order status transition — appends
 * exactly one `statusHistory` entry, populates the matching existing
 * `timestamps` slot (never a new, duplicate concept), bumps `version`
 * implicitly, and — only for a terminal transition — stamps the
 * customer-safe terminal fields (`terminalReasonCode`/`terminalActorType`/
 * `terminalAt`).
 *
 * **`terminalActorUid` is deliberately never written here, on purpose, by
 * design — this document is customer-readable.** A staff member's uid is
 * internal operational data; it belongs only in `auditEvents` (via
 * `writeOrderStatusChangeAuditEvent`), never on a document the order's own
 * customer can read.
 *
 * Callers are responsible for their OWN current-status precondition check
 * BEFORE calling this — this function performs no read and no idempotency
 * check of its own; it assumes the caller has already established that
 * `fromStatus -> toStatus` is a genuinely new transition for this order.
 * Channel-agnostic: works identically for takeaway and delivery orders.
 */
export function applyOrderLifecycleTransition(
  params: ApplyOrderLifecycleTransitionParams,
): void {
  const {
    tx,
    orderRef,
    orderId,
    order,
    fromStatus,
    toStatus,
    actorType,
    now,
    terminalReasonCode,
    refundDisposition,
  } = params;
  const nowIso = now.toDate().toISOString();
  const isTerminal = toStatus === "rejected" || toStatus === "cancelled" || toStatus === "refunded";

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
  if (toStatus === "refunded") {
    update.refundDisposition = refundDisposition ?? null;
  }

  tx.update(orderRef, update);
}

export interface WriteOrderStatusChangeAuditEventParams {
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
 * (already written by `onOrderCreated.ts`/`reservationPreorder.ts`). `actor`
 * is preserved as the existing coarse string field (`"system"`/`"staff"`/
 * `"customer"`, matching the shape every prior writer already used); the
 * newer fields (`branchId`, `actorType`, `actorUid`, `actorRoles`,
 * `reasonCode`, `reasonMessage`) are purely additive.
 *
 * Deterministic document id (`${orderId}-status-${fromStatus}-${toStatus}`)
 * — a given order can only ever make a specific `from -> to` transition
 * once (the state machine has no cycles), so this id can never legitimately
 * collide. `tx.set()`, not `tx.create()`: the true idempotency gate is each
 * callable's own current-status precondition check (re-verified inside the
 * SAME transaction as this write), which already guarantees this function
 * is only ever reached once per real transition. Channel-agnostic: works
 * identically for takeaway and delivery orders.
 */
export function writeOrderStatusChangeAuditEvent(
  params: WriteOrderStatusChangeAuditEventParams,
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
