import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireTakeawayOrderId,
  sanitizeRejectionReasonCode,
  sanitizeOptionalReasonMessage,
  applyTakeawayLifecycleTransition,
  writeTakeawayOrderStatusChangeAuditEvent,
} from "./takeawayOrderLifecycle";

/**
 * `respondToTakeawayOrder` — Boncuk Loyalty Program P4-C-C-B (2026-08-22).
 *
 * The canonical, server-authoritative restaurant response to a
 * `pendingConfirmation` takeaway order — `confirmed` (accept) or
 * `rejected` (refuse before ever accepting). This is the ONLY transition
 * that may ever move a takeaway order out of `pendingConfirmation` into a
 * non-cancelled state; a restaurant refusing an order BEFORE acceptance
 * must always use `decision: "reject"` here, never
 * `cancelTakeawayOrderForStaff` — keeping REJECTED and CANCELLED
 * semantically distinct is a locked product rule (P4-C-C-A §2/§5): a
 * rejected order was never accepted at all, a cancelled order was a
 * previously valid, accepted order terminated early.
 *
 * Staff-only — mirrors `respondToReservation.ts`'s naming, one callable
 * with a `decision` field rather than two separate confirm/reject
 * functions. Requires `manageTakeawayOrders` (the first-ever staff-tier
 * permission in `staffAuthorization.ts`, explicitly approved P4-C-C-A/
 * P4-C-C-B) for the order's own organization, AND branch access
 * (`requireBranchAccess`, the first Cloud-Functions-side branch check in
 * this codebase) for the order's own branch — both derived from the
 * SERVER-LOADED order document, never from client-supplied
 * `organizationId`/`branchId`.
 *
 * **No loyalty write here, by design.** A successful `reject` transition
 * is picked up automatically by the already-built, unmodified
 * `onOrderTerminalFailureOrRefund.ts` trigger (P4-C-B) — writing
 * `status: "rejected"` is all this callable ever needs to do to trigger
 * Boncuk redemption restoration.
 */

const DECISIONS = ["confirm", "reject"] as const;
type Decision = (typeof DECISIONS)[number];

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function sanitizeDecision(raw: unknown): Decision {
  if (typeof raw !== "string" || !(DECISIONS as readonly string[]).includes(raw)) {
    invalid('decision must be "confirm" or "reject".');
  }
  return raw as Decision;
}

export const respondToTakeawayOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireTakeawayOrderId(data.orderId);
    const decision = sanitizeDecision(data.decision);
    const reasonCode = decision === "reject" ? sanitizeRejectionReasonCode(data.reasonCode) : null;
    const reasonMessage =
      decision === "reject" ? sanitizeOptionalReasonMessage(data.reasonMessage) : null;

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "Order not found.");
      }
      const order = orderSnap.data()!;

      if (order.channel !== "takeaway") {
        throw new HttpsError("failed-precondition", "This order is not a takeaway order.");
      }
      const organizationId = order.organizationId as string;
      const branchId = order.branchId as string;

      requireStaffPermission(request, organizationId, "manageTakeawayOrders");
      requireBranchAccess(request, organizationId, branchId);

      const targetStatus: OrderStatus = decision === "confirm" ? "confirmed" : "rejected";
      const currentStatus = order.status as OrderStatus;

      if (currentStatus === targetStatus) {
        return { orderId, status: currentStatus, duplicate: true };
      }
      if (currentStatus !== "pendingConfirmation") {
        throw new HttpsError(
          "failed-precondition",
          `Order is not pendingConfirmation (current status: "${String(currentStatus)}").`,
        );
      }
      if (!canTransition("pendingConfirmation", targetStatus)) {
        // Defensive only — the table already guarantees this today, but
        // this callable must never assume a transition it doesn't itself
        // verify (mirrors onOrderCreated.ts's own discipline).
        throw new HttpsError("failed-precondition", "Transition not allowed.");
      }

      const now = Timestamp.now();
      const actorUid = request.auth!.uid;
      const token = request.auth!.token as Record<string, unknown>;
      const rolesByOrg = token.roles as Record<string, unknown> | undefined;
      const actorRoles = Array.isArray(rolesByOrg?.[organizationId])
        ? (rolesByOrg![organizationId] as string[])
        : null;

      applyTakeawayLifecycleTransition({
        tx,
        orderRef,
        orderId,
        order,
        fromStatus: "pendingConfirmation",
        toStatus: targetStatus,
        actorType: "staff",
        now,
        terminalReasonCode: decision === "reject" ? reasonCode : null,
      });
      writeTakeawayOrderStatusChangeAuditEvent({
        tx,
        db,
        orderId,
        organizationId,
        branchId,
        fromStatus: "pendingConfirmation",
        toStatus: targetStatus,
        actorType: "staff",
        actorUid,
        actorRoles,
        reasonCode: decision === "reject" ? reasonCode : null,
        reasonMessage: decision === "reject" ? reasonMessage : null,
        now,
      });

      return { orderId, status: targetStatus, duplicate: false };
    });
  },
);
