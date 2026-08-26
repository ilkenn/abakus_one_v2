import type { Firestore, Timestamp, Transaction } from "firebase-admin/firestore";

/**
 * AP-2 Stage B — the generic, reusable form of `orderLifecycle.ts`'s
 * `writeOrderStatusChangeAuditEvent`, generalized to any AP-1-canonical
 * `AuditEvent` (`docs/admin_pos_architecture.md` §15) rather than only
 * order-status transitions. Deliberately NOT a rewrite of the order-status
 * writer itself (that function keeps its own existing, tested shape and
 * callers) — this is the shared shape every *new* AP-2 command writes
 * through, so `auditEvents` never grows a second, divergent document shape.
 */
export type AuditActorType = "system" | "staff" | "platform" | "customer" | "device";

export interface WriteAuditEventParams {
  tx: Transaction;
  db: Firestore;
  /** Deterministic, unique per real event occurrence — never reused for a conflicting second event. */
  eventId: string;
  /** `null` for a platform-scoped event with no single owning tenant. */
  organizationId: string | null;
  branchId?: string | null;
  type: string;
  /** Firestore path or id of the record this event describes. */
  targetRef: string;
  previousValue?: unknown;
  newValue?: unknown;
  actorType: AuditActorType;
  actorUid: string | null;
  actorRoles?: readonly string[] | null;
  reasonCode?: string | null;
  reasonMessage?: string | null;
  /** Backend-generated — see `correlationId.ts`. Never client-supplied. */
  correlationId: string;
  /** Sanitized client-supplied idempotency hint, if any — never authoritative. */
  clientRequestId?: string | null;
  now: Timestamp;
}

/**
 * Writes one `auditEvents` document inside the caller's own transaction —
 * AP-2 Stage B Correction #13: a sensitive mutation and its audit event
 * must never be separable (both succeed together or the whole transaction
 * rolls back together). `tx.set()`, not `tx.create()`: callers derive
 * [eventId] deterministically from the specific transition that can only
 * happen once, mirroring `writeOrderStatusChangeAuditEvent`'s own reasoning.
 */
export function writeAuditEvent(params: WriteAuditEventParams): void {
  const {
    tx,
    db,
    eventId,
    organizationId,
    branchId,
    type,
    targetRef,
    previousValue,
    newValue,
    actorType,
    actorUid,
    actorRoles,
    reasonCode,
    reasonMessage,
    correlationId,
    clientRequestId,
    now,
  } = params;
  tx.set(db.collection("auditEvents").doc(eventId), {
    organizationId,
    branchId: branchId ?? null,
    type,
    targetRef,
    previousValue: previousValue ?? null,
    newValue: newValue ?? null,
    actor: actorType,
    actorType,
    actorUid: actorUid ?? null,
    actorRoles: actorRoles ?? null,
    reasonCode: reasonCode ?? null,
    reasonMessage: reasonMessage ?? null,
    correlationId,
    clientRequestId: clientRequestId ?? null,
    timestamp: now.toDate().toISOString(),
  });
}
