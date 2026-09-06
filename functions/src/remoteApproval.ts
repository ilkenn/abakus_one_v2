import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import type { Firestore, Transaction } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import type { StaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import { applyDeviceActivation } from "./trustedDevice";
import {
  applyCheckFinancialAdjustment,
  applyAcceptedLineCancellation,
  applyBoncukBalanceCorrection,
} from "./checkFinancialAdjustments";
import { applyPaymentRefund, applyPaymentRefundRejected } from "./paymentRefund";
import {
  applyCashSessionOpen,
  applyCashSessionOpenRejected,
  applyCashMovement,
  applyCashMovementRejected,
  applyCashAdjustment,
  applyCashAdjustmentRejected,
  applyCashReconciliationApproved,
  applyCashReconciliationRejected,
} from "./cashRegisterEngine";

/**
 * AP-2 Stage B — the generic, server-authoritative remote approval engine
 * (`docs/admin_pos_architecture.md` §16). Deliberately scoped this phase to
 * exactly ONE allowlisted action type (`deviceActivation`) — Correction #6:
 * "Generic engine arbitrary callable adı veya arbitrary payload
 * çalıştırmamalıdır. Yalnız allowlisted, typed action handler'ları
 * çalıştırmalıdır." [ACTION_HANDLERS] below is a closed, compile-time-typed
 * map, not an open runtime registry — adding a second action type in AP-3+
 * means adding a case here, never accepting an arbitrary string.
 *
 * **Known, explicit simplification (documented, not silently dropped)**:
 * full escalation to a Platform Owner who can then directly respond is NOT
 * implemented this phase — Platform Owner and tenant-staff authorization
 * are separate custom-claim namespaces by design (ADR-025), and building a
 * safe cross-namespace "Platform Owner may respond to a tenant approval"
 * path is real, separate design work (would need something like
 * `hasActiveSupportGrant`'s temporary-elevated-access shape), not something
 * to improvise under this phase's own time budget. [sweepExpiredApprovalRequests]
 * transitions an unanswered request to `escalated` (writes a
 * `notificationOutbox` entry flagging human intervention) on its first
 * pass, then to the terminal `expired` on a second pass if still
 * unanswered — matching the documented state machine's shape, but without
 * a real "new pending request for a new approver" step yet.
 */

export type ApprovalStatus = "pending" | "approved" | "rejected" | "expired" | "escalated" | "cancelled";
export type ApprovalActionType =
  | "deviceActivation"
  // AP-3 Wave 2C/2D — corrected report §3/§4, Stage B mandatory refinements
  // #5/#9. Each is its own typed action with its own allowlisted handler —
  // never a generic "apply this arbitrary payload" action.
  | "checkFinancialAdjustment"
  | "acceptedLineCancellation"
  | "boncukBalanceCorrection"
  // AP-4 Wave A (ADR-033) — a staff-requested refund that requires manager
  // approval before any money actually moves. Same typed-handler discipline
  // as every action above. Also has a REJECTION_HANDLERS entry (added AP-4
  // Wave F, 2026-09-07) — a rejected refund request must transition its own
  // refundRequests doc to "rejected", or its reservation against the
  // check's refundable remainder would never be released (see
  // applyPaymentRefundRejected's own doc comment for the confirmed bug this
  // closes).
  | "paymentRefund"
  // AP-4 Wave B (ADR-045) — cash register lifecycle actions. Unlike most
  // action above, these four have a REJECTION_HANDLERS entry too (see
  // below) — a rejected cash session-open/reconciliation is a real state
  // change (session -> openRejected/rejected), not a no-op.
  | "cashSessionOpen"
  | "cashMovement"
  | "cashAdjustment"
  | "cashReconciliation";

const APPROVAL_TIMEOUT_MINUTES = 24 * 60;
const ESCALATION_TIMEOUT_MINUTES = 24 * 60;

export interface ApprovalRequestRecord {
  requestId: string;
  organizationId: string;
  branchId: string;
  actionType: ApprovalActionType;
  requestedByActorUid: string;
  targetAggregateRef: string;
  targetAggregateVersion: number;
  payloadHash: string;
  status: ApprovalStatus;
  respondedByActorUid: string | null;
  respondedAt: Timestamp | null;
  escalatedTo: string | null;
  createdAt: Timestamp;
  expiresAt: Timestamp;
  version: number;
}

export interface ActionHandlerResult {
  newValue: unknown;
}

export interface ActionHandlerParams {
  tx: Transaction;
  db: Firestore;
  request: ApprovalRequestRecord;
  now: Timestamp;
  /**
   * AP-3 Wave 2 addition — the responder's own uid. `request.respondedByActorUid`
   * is NOT yet set to this value at the point a handler runs (the handler
   * executes BEFORE `respondToApprovalRequest`'s own `tx.update(ref,
   * {respondedByActorUid, ...})` write, so it can decide whether to apply
   * anything at all before that field is committed) — a handler that needs
   * to record who approved it (e.g. `applyAcceptedLineCancellation`'s own
   * provenance trail) must read it from here, never from `request` itself.
   */
  respondedByActorUid: string;
}

type ActionHandler = (params: ActionHandlerParams) => Promise<ActionHandlerResult>;

/**
 * The closed, allowlisted action registry — the ONLY way a `respondToApprovalRequest`
 * approval can ever mutate anything. Each handler independently re-verifies its own
 * target's current version inside the same transaction (stale-target protection),
 * never trusting the approval record's own [targetAggregateVersion] as still current
 * without checking.
 */
const ACTION_HANDLERS: Readonly<Record<ApprovalActionType, ActionHandler>> = {
  deviceActivation: applyDeviceActivation,
  checkFinancialAdjustment: applyCheckFinancialAdjustment,
  acceptedLineCancellation: applyAcceptedLineCancellation,
  boncukBalanceCorrection: applyBoncukBalanceCorrection,
  paymentRefund: applyPaymentRefund,
  cashSessionOpen: applyCashSessionOpen,
  cashMovement: applyCashMovement,
  cashAdjustment: applyCashAdjustment,
  cashReconciliation: applyCashReconciliationApproved,
};

/**
 * AP-4 Wave B addition, extended AP-4 Wave F (2026-09-07). OPTIONAL,
 * additive-only. `deviceActivation`/`checkFinancialAdjustment`/
 * `acceptedLineCancellation`/`boncukBalanceCorrection` have no entry here,
 * so a rejection of any of those behaves exactly as before (the target
 * aggregate is left untouched — there is nothing to roll back for those).
 * Cash register actions and `paymentRefund` are different: a rejection is
 * itself a real, required state transition (`awaitingOpenApproval ->
 * openRejected`, `pendingApproval -> rejected`), not a no-op — for
 * `paymentRefund` specifically, omitting this entry was a confirmed bug
 * (Wave F): the refundRequests doc stayed "pendingApproval" forever after
 * rejection, permanently reserving its amount against the check's
 * refundable remainder (`requestPaymentRefund`'s own `where("status", "!=",
 * "failed")` reservation query) and blocking any correct re-request. This
 * map is consulted ONLY when `decision === "rejected"`, immediately below
 * the existing approved-only dispatch, so every other pre-existing action
 * type's contract is unchanged.
 */
const REJECTION_HANDLERS: Readonly<Partial<Record<ApprovalActionType, ActionHandler>>> = {
  cashSessionOpen: applyCashSessionOpenRejected,
  cashMovement: applyCashMovementRejected,
  cashAdjustment: applyCashAdjustmentRejected,
  cashReconciliation: applyCashReconciliationRejected,
  paymentRefund: applyPaymentRefundRejected,
};

/** The staff permission required to RESPOND to (approve/reject) each action type — never a bare role-tier check. */
const RESPONSE_PERMISSION_BY_ACTION: Readonly<Record<ApprovalActionType, StaffPermission>> = {
  deviceActivation: "approveDeviceRegistration",
  checkFinancialAdjustment: "approveCheckFinancialAdjustment",
  acceptedLineCancellation: "approveAcceptedLineCancellation",
  boncukBalanceCorrection: "approveBoncukBalanceCorrection",
  paymentRefund: "approvePaymentRefund",
  cashSessionOpen: "approveCashReconciliation",
  cashMovement: "approveCashReconciliation",
  cashAdjustment: "approveCashReconciliation",
  cashReconciliation: "approveCashReconciliation",
};

/**
 * AP-4 Wave F security fix (2026-09-07) — the responder's own branch access
 * was never checked, only their organization-level permission
 * (`RESPONSE_PERMISSION_BY_ACTION`), even though every REQUESTING callable
 * for these same action types (`requestPaymentRefund`, `authorizeCashCommand`
 * — used by the cash actions, `requestCheckFinancialAdjustment`) already
 * checks the requester's `requireBranchAccess`. Confirmed exploitable:
 * `remoteApprovalMatrix.test.ts`'s "GAP — wrong-branch approver" tests
 * proved a manager scoped only to Branch B could approve a
 * paymentRefund/cashMovement/checkFinancialAdjustment request that
 * originated at Branch A.
 *
 * Deliberately scoped to the financial action types only —
 * `deviceActivation` is excluded on purpose. Org-wide device-fleet
 * oversight by an org admin (who, by design, starts with `branchAccess: []`
 * — `staffAuthorization.ts`'s own "no wildcard branch access, not even for
 * admin/tenantOwner" rule) is a pre-existing, widely-relied-upon authority
 * model (`activeDeviceSession`'s own test fixture, reused unmodified across
 * 13 files / 28 call sites, always approves as the org admin) and was never
 * part of the reported vulnerability — broadening this fix to
 * `deviceActivation` would be an unrelated, large-blast-radius behavior
 * change to a working, intentional design, not a fix to the actual gap.
 * Physical-cash/financial actions are different: they're tied to a specific
 * branch's own drawer/register/check, so branch-scoping the *response*,
 * matching every request-side check already in place, is the correct fix.
 *
 * `boncukBalanceCorrection` is ALSO deliberately excluded, for a different
 * reason discovered while verifying this fix against the existing test
 * suite: unlike every other type here, it operates on a CUSTOMER's loyalty
 * account, which is organization-scoped, not branch-scoped —
 * `requestBoncukBalanceCorrection` itself never takes a `branchId` and
 * always creates its approval request with the literal sentinel
 * `branchId: "platform"` (`checkFinancialAdjustments.ts`), which would never
 * match any real staff member's `branchAccess` grant. Including it here
 * would have made every boncuk correction unapprovable by anyone, confirmed
 * by `checkFinancialAdjustments.test.ts`'s own pre-existing test failing
 * with exactly that error the moment this fix was first tried with it
 * included.
 */
const BRANCH_SCOPED_RESPONSE_ACTION_TYPES: ReadonlySet<ApprovalActionType> = new Set([
  "checkFinancialAdjustment",
  "acceptedLineCancellation",
  "paymentRefund",
  "cashSessionOpen",
  "cashMovement",
  "cashAdjustment",
  "cashReconciliation",
]);

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) invalid(`${field} is required.`);
  return value as string;
}
/**
 * AP-2 final wiring — optional, sanitized responder rationale. Kept
 * OPTIONAL at this backend layer (unlike `revokeTrustedDevice`'s required
 * `reason`) so the existing, already-tested `respondToApprovalRequest`
 * call sites that predate this field keep working unchanged; the Flutter
 * Approval Inbox UI enforces "mandatory reason" at the client boundary
 * instead. `null` (not stored) rather than an empty string when absent or
 * invalid — mirrors [sanitizeClientRequestId]'s own null-on-invalid shape.
 */
function sanitizeReasonMessage(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 500) return null;
  return trimmed;
}

/**
 * Creates (or idempotently returns) a pending approval request. Deterministic
 * [requestId] derived from the target + action + version — a second request for
 * the SAME target at the SAME version reuses the existing pending request rather
 * than creating a duplicate. Never directly callable by a client — always invoked
 * server-side, as part of an already-authorized action (e.g.
 * `requestDeviceRegistration`), which is what actually authorizes the request's
 * existence; this function itself does not re-check permission.
 */
export async function createApprovalRequest(params: {
  organizationId: string;
  branchId: string;
  actionType: ApprovalActionType;
  requestedByActorUid: string;
  targetAggregateRef: string;
  targetAggregateVersion: number;
  payloadHash: string;
}): Promise<{ requestId: string; status: ApprovalStatus }> {
  const db = getFirestore();
  const requestId = `approval-${params.actionType}-${params.targetAggregateRef.replace(/\//g, "_")}-v${params.targetAggregateVersion}`;
  const ref = db.collection("remoteApprovalRequests").doc(requestId);
  const existing = await ref.get();
  if (existing.exists) {
    return { requestId, status: (existing.data() as ApprovalRequestRecord).status };
  }
  const now = Timestamp.now();
  const record: ApprovalRequestRecord = {
    requestId,
    organizationId: params.organizationId,
    branchId: params.branchId,
    actionType: params.actionType,
    requestedByActorUid: params.requestedByActorUid,
    targetAggregateRef: params.targetAggregateRef,
    targetAggregateVersion: params.targetAggregateVersion,
    payloadHash: params.payloadHash,
    status: "pending",
    respondedByActorUid: null,
    respondedAt: null,
    escalatedTo: null,
    createdAt: now,
    expiresAt: Timestamp.fromMillis(now.toMillis() + APPROVAL_TIMEOUT_MINUTES * 60_000),
    version: 1,
  };
  await ref.set(record);
  return { requestId, status: "pending" };
}

/**
 * Approves or rejects a pending request. Self-approval structurally
 * forbidden (the requester can never respond to their own request,
 * regardless of permission). An already-resolved request with the SAME
 * decision from the SAME responder is a safe idempotent no-op (returns the
 * existing result); a conflicting second response (different decision, or
 * from a different responder) is rejected with `failed-precondition`. A
 * `pending` request whose `expiresAt` has already passed is treated as
 * expired here even before the sweep formally transitions it.
 */
export const respondToApprovalRequest = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
    const data = (request.data ?? {}) as Record<string, unknown>;
    const requestId = requireNonEmptyString(data.requestId, "requestId");
    const decision = requireNonEmptyString(data.decision, "decision");
    if (decision !== "approved" && decision !== "rejected") {
      invalid('decision must be "approved" or "rejected".');
    }

    const db = getFirestore();
    const ref = db.collection("remoteApprovalRequests").doc(requestId);
    const preSnap = await ref.get();
    if (!preSnap.exists) {
      throw new HttpsError("not-found", "No approval request found for this id.");
    }
    const pre = preSnap.data() as ApprovalRequestRecord;

    if (pre.requestedByActorUid === request.auth.uid) {
      throw new HttpsError("permission-denied", "The requester cannot respond to their own approval request.");
    }
    requireStaffPermission(request, pre.organizationId, RESPONSE_PERMISSION_BY_ACTION[pre.actionType]);
    if (BRANCH_SCOPED_RESPONSE_ACTION_TYPES.has(pre.actionType)) {
      requireBranchAccess(request, pre.organizationId, pre.branchId);
    }

    if (pre.status === decision && pre.respondedByActorUid === request.auth.uid) {
      return { requestId, status: pre.status, idempotent: true };
    }
    if (pre.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        `This request is already ${pre.status} — a conflicting second response is rejected.`,
      );
    }

    const correlationId = generateCorrelationId();
    const clientRequestId = sanitizeClientRequestId(data.clientRequestId);
    const reasonMessage = sanitizeReasonMessage(data.reasonMessage);

    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current = snap.data() as ApprovalRequestRecord;
      const now = Timestamp.now();

      if (current.status !== "pending") {
        throw new HttpsError("failed-precondition", `This request is already ${current.status}.`);
      }
      if (current.expiresAt.toMillis() < now.toMillis()) {
        tx.update(ref, { status: "expired" as ApprovalStatus, version: current.version + 1 });
        throw new HttpsError("failed-precondition", "This request has expired.");
      }

      let newValue: unknown = null;
      if (decision === "approved") {
        const handler = ACTION_HANDLERS[current.actionType];
        const handlerResult = await handler({ tx, db, request: current, now, respondedByActorUid: request.auth!.uid });
        newValue = handlerResult.newValue;
      } else {
        const rejectionHandler = REJECTION_HANDLERS[current.actionType];
        if (rejectionHandler) {
          const handlerResult = await rejectionHandler({ tx, db, request: current, now, respondedByActorUid: request.auth!.uid });
          newValue = handlerResult.newValue;
        }
      }

      tx.update(ref, {
        status: decision as ApprovalStatus,
        respondedByActorUid: request.auth!.uid,
        respondedAt: now,
        version: current.version + 1,
      });

      // Approval history — immutable, auto-generated unique id (never
      // `{requestId}_{eventType}`, which could collide if the same event
      // type were ever legitimately possible twice for one request).
      const eventRef = db.collection("approvalEvents").doc();
      tx.set(eventRef, {
        requestId,
        organizationId: current.organizationId,
        branchId: current.branchId,
        actionType: current.actionType,
        eventType: decision === "approved" ? "approval.approved" : "approval.rejected",
        respondedByActorUid: request.auth!.uid,
        reasonMessage,
        correlationId,
        clientRequestId,
        timestamp: now.toDate().toISOString(),
      });

      writeAuditEvent({
        tx,
        db,
        eventId: `${requestId}-${decision}-v${current.version + 1}`,
        organizationId: current.organizationId,
        branchId: current.branchId,
        type: decision === "approved" ? "approval.approved" : "approval.rejected",
        targetRef: current.targetAggregateRef,
        previousValue: null,
        newValue,
        actorType: "staff",
        actorUid: request.auth!.uid,
        reasonMessage: reasonMessage ?? undefined,
        correlationId,
        clientRequestId,
        now,
      });

      return { status: decision as ApprovalStatus };
    });

    return { requestId, status: result.status, idempotent: false, correlationId };
  },
);

/**
 * Sweeps `pending` requests past their `expiresAt` — mirrors
 * `reservationSweep.ts`'s own real, tested sweep-function precedent
 * exactly (a callable that can be invoked directly or wired to Cloud
 * Scheduler later; not itself a scheduled binding this phase). First pass:
 * `pending` -> `escalated` (writes a `notificationOutbox` entry flagging
 * that human Platform Owner intervention is needed — see this file's own
 * top comment on the known simplification). Second pass: an `escalated`
 * request past `expiresAt + ESCALATION_TIMEOUT_MINUTES` -> terminal `expired`.
 */
export const sweepExpiredApprovalRequests = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();

    const pendingSnap = await db
      .collection("remoteApprovalRequests")
      .where("status", "==", "pending")
      .get();
    let escalated = 0;
    for (const doc of pendingSnap.docs) {
      const record = doc.data() as ApprovalRequestRecord;
      if (record.expiresAt.toMillis() >= now.toMillis()) continue;
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        const current = snap.data() as ApprovalRequestRecord;
        if (current.status !== "pending") return;
        tx.update(doc.ref, {
          status: "escalated" as ApprovalStatus,
          escalatedTo: "platformOwner",
          expiresAt: Timestamp.fromMillis(now.toMillis() + ESCALATION_TIMEOUT_MINUTES * 60_000),
          version: current.version + 1,
        });
        tx.set(db.collection("approvalEvents").doc(), {
          requestId: current.requestId,
          organizationId: current.organizationId,
          branchId: current.branchId,
          actionType: current.actionType,
          eventType: "approval.escalated",
          respondedByActorUid: null,
          correlationId: generateCorrelationId(),
          clientRequestId: null,
          timestamp: now.toDate().toISOString(),
        });
        // Notification outbox — a SEPARATE, mutable, backend-only
        // delivery-tracking collection, never the same model as the
        // immutable approvalEvents history above.
        tx.set(db.collection("notificationOutbox").doc(), {
          organizationId: current.organizationId,
          branchId: current.branchId,
          type: "approval.escalationNeeded",
          targetRef: `remoteApprovalRequests/${current.requestId}`,
          deliveryStatus: "pending",
          deliveryAttempts: 0,
          leaseExpiresAt: null,
          createdAt: now,
        });
      });
      escalated += 1;
    }

    const escalatedSnap = await db
      .collection("remoteApprovalRequests")
      .where("status", "==", "escalated")
      .get();
    let expired = 0;
    for (const doc of escalatedSnap.docs) {
      const record = doc.data() as ApprovalRequestRecord;
      if (record.expiresAt.toMillis() >= now.toMillis()) continue;
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        const current = snap.data() as ApprovalRequestRecord;
        if (current.status !== "escalated") return;
        tx.update(doc.ref, { status: "expired" as ApprovalStatus, version: current.version + 1 });
        tx.set(db.collection("approvalEvents").doc(), {
          requestId: current.requestId,
          organizationId: current.organizationId,
          branchId: current.branchId,
          actionType: current.actionType,
          eventType: "approval.expired",
          respondedByActorUid: null,
          correlationId: generateCorrelationId(),
          clientRequestId: null,
          timestamp: now.toDate().toISOString(),
        });
      });
      expired += 1;
    }

    return { escalated, expired };
  },
);
