import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";

/**
 * `transitionKitchenWorkItem` — AP-5 Sprint 1.
 *
 * The server-authoritative mirror of `TransitionKitchenWorkItem`
 * (`lib/features/pos/application/use_cases/transition_kitchen_work_item.dart`)
 * — same `KitchenLineStatus` state machine (`kitchen_line_status.dart`'s
 * `KitchenLineStatusTransitions`, ported verbatim below, not redesigned),
 * same optimistic-concurrency check (`expectedRevision` vs. the document's
 * own `revision`). This closes the confirmed AP-0/AP-1 gap: the KDS board's
 * `KitchenWorkItem` state was entirely in-memory and never reached a real
 * backend.
 *
 * Deliberately does **not** itself call `advanceDineInOrderStatus`/
 * `advanceTakeawayOrderStatus` — composing this transaction with either of
 * those channels' own carefully-tested next-status tables (e.g.
 * `advanceTakeawayOrderStatus`'s `ready -> completed` triggering Boncuk
 * earning) here would mean re-deriving or duplicating logic this function
 * has no need to know. Instead, when the transition to `ready` makes every
 * sibling work item for the same order `ready` (or `cancelled`), this
 * returns `allSiblingsReady: true` and the order's `channel` — the CLIENT
 * (`KitchenDisplayBoardScreen`) makes the second, already-existing callable
 * call itself, exactly as the kickoff instruction asked ("the board's
 * advance actions integrate with the advance*OrderStatus calls").
 */

type KitchenLineStatus =
  | "queued"
  | "acknowledged"
  | "preparing"
  | "ready"
  | "cancelled"
  | "unavailable"
  | "recalled"
  | "wasted";

// Ported verbatim from `KitchenLineStatusTransitions` — same table, same
// terminal states (`cancelled`/`unavailable`/`wasted` have no outgoing
// transition; `ready` may only go to `recalled`/`wasted`, never silently
// back to `preparing`). `wasted` — AP-5 Sprint 3 — is reachable only from
// `preparing`/`ready` (real stock already consumed); `queued`/
// `acknowledged` still terminate via `cancelled` only, since nothing was
// consumed yet for them to waste.
const ALLOWED_TRANSITIONS: Readonly<Record<KitchenLineStatus, readonly KitchenLineStatus[]>> = {
  queued: ["acknowledged", "cancelled", "unavailable"],
  acknowledged: ["preparing", "cancelled", "unavailable"],
  preparing: ["ready", "cancelled", "unavailable", "wasted"],
  ready: ["recalled", "wasted"],
  recalled: ["preparing"],
  cancelled: [],
  unavailable: [],
  wasted: [],
};

const VALID_STATUSES = Object.keys(ALLOWED_TRANSITIONS) as readonly KitchenLineStatus[];

function canTransition(from: KitchenLineStatus, to: KitchenLineStatus): boolean {
  if (from === to) return false;
  return ALLOWED_TRANSITIONS[from]?.includes(to) ?? false;
}

function requireWorkItemId(raw: unknown): string {
  if (typeof raw !== "string" || raw.length === 0) {
    throw new HttpsError("invalid-argument", "workItemId is required.");
  }
  return raw;
}

function requireTargetStatus(raw: unknown): KitchenLineStatus {
  if (typeof raw !== "string" || !VALID_STATUSES.includes(raw as KitchenLineStatus)) {
    throw new HttpsError("invalid-argument", `to must be one of: ${VALID_STATUSES.join(", ")}.`);
  }
  return raw as KitchenLineStatus;
}

function requireExpectedRevision(raw: unknown): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 1) {
    throw new HttpsError("invalid-argument", "expectedRevision must be a positive integer.");
  }
  return raw;
}

const TIMESTAMP_FIELD_BY_STATUS: Partial<Record<KitchenLineStatus, string>> = {
  acknowledged: "acknowledgedAt",
  preparing: "preparingStartedAt",
  ready: "readyAt",
  wasted: "wastedAt",
  cancelled: "cancelledAt",
  unavailable: "unavailableAt",
  recalled: "recalledAt",
};

export const transitionKitchenWorkItem = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const workItemId = requireWorkItemId(data.workItemId);
    const to = requireTargetStatus(data.to);
    const expectedRevision = requireExpectedRevision(data.expectedRevision);
    const reason = typeof data.reason === "string" ? data.reason : null;

    const db = getFirestore();
    const workItemRef = db.collection("kitchenWorkItems").doc(workItemId);

    return db.runTransaction(async (tx) => {
      // --- reads first (Firestore transactions require every read before
      // the first write) ---
      const snap = await tx.get(workItemRef);
      if (!snap.exists) {
        throw new HttpsError("not-found", "Kitchen work item not found.");
      }
      const item = snap.data()!;
      const organizationId = item.organizationId as string;
      const branchId = item.branchId as string;
      const orderId = item.orderId as string;
      const currentStatus = item.status as KitchenLineStatus;
      const currentRevision = item.revision as number;

      requireStaffPermission(request, organizationId, "manageKitchenOperations");
      requireBranchAccess(request, organizationId, branchId);

      if (currentRevision !== expectedRevision) {
        throw new HttpsError(
          "failed-precondition",
          `Stale revision: expected ${expectedRevision}, item is at ${currentRevision}.`,
        );
      }
      if (!canTransition(currentStatus, to)) {
        throw new HttpsError(
          "failed-precondition",
          `Cannot transition from "${currentStatus}" to "${to}".`,
        );
      }

      let siblingsSnap: FirebaseFirestore.QuerySnapshot | null = null;
      let orderChannel: string | null = null;
      if (to === "ready") {
        siblingsSnap = await tx.get(
          db.collection("kitchenWorkItems").where("orderId", "==", orderId),
        );
        // Read-only lookup so the client can pick the right advance*OrderStatus
        // callable (dineIn/takeaway/delivery/reservationPreorder each have
        // their own) without KitchenTicket/KitchenWorkItem needing to carry
        // the raw channel themselves — today they only expose a display
        // label (`channelLabel`), never the raw `OrderChannel` value.
        const orderSnap = await tx.get(db.collection("orders").doc(orderId));
        orderChannel = orderSnap.exists ? ((orderSnap.data()?.channel as string) ?? null) : null;
      }

      // --- writes ---
      const now = Timestamp.now();
      const newRevision = currentRevision + 1;
      const timestampField = TIMESTAMP_FIELD_BY_STATUS[to];
      const update: Record<string, unknown> = { status: to, revision: newRevision };
      if (timestampField) {
        update[timestampField] = now;
      }
      tx.update(workItemRef, update);

      tx.set(db.collection("kitchenAuditEntries").doc(`${workItemId}-rev${newRevision}`), {
        organizationId,
        branchId,
        orderId,
        kitchenTicketId: item.kitchenTicketId ?? null,
        workItemId,
        previousStatus: currentStatus,
        newStatus: to,
        actorUid: request.auth!.uid,
        reason,
        timestamp: now,
      });

      let allSiblingsReady = false;
      if (to === "ready" && siblingsSnap) {
        allSiblingsReady = siblingsSnap.docs.every((doc) => {
          // This item's own write above hasn't been read back within this
          // same transaction — it's still `currentStatus` in `siblingsSnap`
          // — so its own doc is treated as `ready` explicitly here.
          if (doc.id === workItemId) return true;
          const siblingStatus = doc.data().status as KitchenLineStatus;
          return siblingStatus === "ready" || siblingStatus === "cancelled";
        });
      }

      return {
        workItemId,
        status: to,
        revision: newRevision,
        allSiblingsReady,
        orderId: to === "ready" ? orderId : null,
        orderChannel: to === "ready" ? orderChannel : null,
      };
    });
  },
);
