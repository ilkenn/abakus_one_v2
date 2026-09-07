import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import { prepareKitchenWorkAndStockConsumption, applyKitchenWorkAndStockConsumption } from "./acceptOrderLine";
import { preparePrintJobForAcceptance, applyPrintJobPlan } from "./printJobEngine";

/**
 * AP-3 Wave 1 — per-line accept/reject for a `guestSession`-mode
 * `submitDineInOrder` submission (corrected Stage A report §10/#11).
 * `staffEntry`-mode orders are written `accepted` at create time and are
 * never a valid target here — a trusted, permission- and device-checked
 * staff entry IS the approval; routing it back through this callable would
 * reintroduce the self-approval loop the corrected report required removed.
 *
 * **Deferred, disclosed boundary (Wave 1)**: only `accept`/`reject` are
 * implemented this pass. The counter-proposal path (`propose` — an
 * immutable product/modifier/quantity/price-difference snapshot, with its
 * own accept/reject/expiry lifecycle, corrected report §9/§12) is NOT
 * implemented yet — `lines[i].counterProposal` stays `null` for every line
 * this callable ever touches. A future Wave 1 continuation adds it as its
 * own decision kind without needing to revisit this file's accept/reject
 * shape.
 */

type LineDecision = "accept" | "reject";
interface LineDecisionInput {
  lineIndex: number;
  decision: LineDecision;
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function sanitizeDecisions(raw: unknown): LineDecisionInput[] {
  if (!Array.isArray(raw) || raw.length === 0) invalid("decisions must be a non-empty array.");
  const seen = new Set<number>();
  return raw.map((entry) => {
    if (typeof entry !== "object" || entry === null) invalid("Each decision must be an object.");
    const value = entry as Record<string, unknown>;
    if (typeof value.lineIndex !== "number" || !Number.isInteger(value.lineIndex) || value.lineIndex < 0) {
      invalid("decision.lineIndex must be a non-negative integer.");
    }
    if (value.decision !== "accept" && value.decision !== "reject") {
      invalid('decision.decision must be "accept" or "reject".');
    }
    if (seen.has(value.lineIndex)) invalid(`Duplicate decision for lineIndex ${value.lineIndex}.`);
    seen.add(value.lineIndex);
    return { lineIndex: value.lineIndex, decision: value.decision as LineDecision };
  });
}

export const respondToDineInOrderLines = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.orderId !== "string" || data.orderId.length === 0) {
      invalid("orderId is required.");
    }
    const orderId = data.orderId as string;
    const decisions = sanitizeDecisions(data.decisions);

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "Order not found.");
      }
      const order = orderSnap.data()!;

      requireStaffPermission(request, order.organizationId, "manageDineInOrders");
      requireBranchAccess(request, order.organizationId, order.branchId);

      if (order.channel !== "dineInQr") {
        throw new HttpsError("failed-precondition", "This order is not a dine-in table order.");
      }
      if (order.mode === "staffEntry") {
        throw new HttpsError(
          "failed-precondition",
          "Staff-entered order lines are already accepted and cannot be responded to.",
        );
      }

      const lines = Array.isArray(order.lines) ? [...order.lines] : [];
      for (const { lineIndex, decision } of decisions) {
        if (lineIndex >= lines.length) {
          throw new HttpsError("invalid-argument", `lineIndex ${lineIndex} is out of range.`);
        }
        const line = lines[lineIndex];
        if (line.status !== "pendingApproval") {
          throw new HttpsError(
            "failed-precondition",
            `Line ${lineIndex} is not pending (current status: ${line.status}).`,
          );
        }
        lines[lineIndex] = {
          ...line,
          status: decision === "accept" ? "accepted" : "rejected",
        };
      }

      const stillPending = lines.some((line) => line.status === "pendingApproval");
      const anyResolved = lines.some((line) => line.status === "accepted" || line.status === "rejected");
      const linesDispositionSummary = stillPending
        ? anyResolved
          ? "partiallyResolved"
          : "pending"
        : "resolved";

      const now = Timestamp.now();

      // AP-5 Sprint 2 — read phase must run BEFORE this transaction's
      // first write (`tx.update(orderRef, ...)` below), per this
      // codebase's own Firestore-transaction discipline
      // (`submitDineInOrder.ts`'s "every tx.get() happens before its
      // first write"). Kitchen enqueue + stock/packaging consumption is
      // computed for exactly the line(s) THIS call just accepted — a
      // `reject` decision never triggers either.
      const acceptedLines = decisions
        .filter((d) => d.decision === "accept")
        .map((d) => ({
          orderLineId: `kt-${orderId}-line-${d.lineIndex}`,
          productId: lines[d.lineIndex].productId as string,
          quantity: lines[d.lineIndex].quantity as number,
        }));
      const stockPlan =
        acceptedLines.length > 0
          ? await prepareKitchenWorkAndStockConsumption({
              tx,
              db,
              organizationId: order.organizationId,
              branchId: order.branchId,
              orderId,
              channel: "dineInQr",
              acceptedLines,
              performedByUid: request.auth!.uid,
              now,
            })
          : null;
      // AP-5 Sprint 4 — one print job per order, opened at the same point
      // as kitchen enqueue/stock consumption (read phase, before this
      // transaction's own first write). Idempotent via
      // `preparePrintJobForAcceptance`'s own deterministic-id check, so a
      // retried/duplicate call never opens a second job.
      const printPlan =
        acceptedLines.length > 0
          ? await preparePrintJobForAcceptance({
              tx,
              db,
              organizationId: order.organizationId,
              branchId: order.branchId,
              orderId,
              stationId: "shared",
              now,
            })
          : null;

      tx.update(orderRef, { lines, linesDispositionSummary });
      applyKitchenWorkAndStockConsumption(tx, db, stockPlan);
      applyPrintJobPlan(tx, db, printPlan);

      writeAuditEvent({
        tx,
        db,
        eventId: `${orderId}-lines-response-${now.toMillis()}`,
        organizationId: order.organizationId,
        branchId: order.branchId,
        type: "order.dineInLinesResponded",
        targetRef: orderRef.path,
        newValue: { decisions, linesDispositionSummary },
        actorType: "staff",
        actorUid: request.auth!.uid,
        correlationId: generateCorrelationId(),
        clientRequestId: sanitizeClientRequestId(data.clientRequestId),
        now,
      });

      return { orderId, linesDispositionSummary };
    });
  },
);
