import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import { loadCanonicalChannelPricingPolicy, loadCanonicalMenuProduct } from "./takeawayCatalog";
import { buildProductLine, type RawProductItem } from "./submitTakeawayOrder";
import { computeLineValueMinorUnits } from "./checkAllocationConfig";

/**
 * AP-3 Wave 2 remainder — the QR replacement/counter-proposal backend
 * (corrected report §9/§12). A staff-proposed line replacement, resolved
 * through the SAME canonical pricing pipeline `submitDineInOrder` itself
 * uses (`buildProductLine`, never a hand-rolled recompute), stored as an
 * immutable snapshot on the order line, with its own accept/reject/expiry
 * lifecycle. **Product lines only this pass** — Bowl Builder line
 * replacement is explicitly deferred (disclosed, not silently dropped);
 * `proposeDineInLineReplacement` rejects a target line whose ORIGINAL kind
 * cannot be determined as a plain product line.
 *
 * Never reachable for a `staffEntry`-mode order (already-accepted lines,
 * per corrected report §10 — nothing to propose a replacement against) or
 * for a line not currently `pendingApproval`.
 */

const DINE_IN_COMMERCIAL_CHANNEL = "dineIn";
const COUNTER_PROPOSAL_TTL_MINUTES = 15;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}
function requirePositiveInt(raw: unknown, field: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0) invalid(`${field} must be a positive integer.`);
  return raw as number;
}

interface CounterProposalSnapshot {
  proposalVersion: number;
  proposedProductId: string;
  proposedProductName: string;
  proposedModifiers: Array<{ groupId: string; groupName: string; optionId: string; optionName: string; unitExtraPrice: { minorUnits: number; currencyCode: string }; quantity: number }>;
  proposedQuantity: number;
  proposedUnitPrice: { minorUnits: number; currencyCode: string };
  proposedLineTotalMinorUnits: number;
  differenceFromOriginalMinorUnits: number;
  reasonCode: string;
  reasonMessage: string;
  proposedByStaffUid: string;
  createdAt: Timestamp;
  expiresAt: Timestamp;
  status: "pendingCustomerResponse" | "accepted" | "rejected" | "expired";
  respondedAt: Timestamp | null;
}

/** Recomputes the order's earliest-still-pending-proposal expiry across every line — the denormalized top-level field the sweep queries on (nested-array Firestore queries aren't possible; mirrors this codebase's own established denormalize-for-queryability convention). */
function computeEarliestPendingProposalExpiresAt(lines: Array<Record<string, unknown>>): Timestamp | null {
  let earliest: Timestamp | null = null;
  for (const line of lines) {
    const proposal = line.counterProposal as CounterProposalSnapshot | null | undefined;
    if (!proposal || proposal.status !== "pendingCustomerResponse") continue;
    if (!earliest || proposal.expiresAt.toMillis() < earliest.toMillis()) earliest = proposal.expiresAt;
  }
  return earliest;
}

export const proposeDineInLineReplacement = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  const orderId = requireNonEmptyString(data.orderId, "orderId");
  if (typeof data.lineIndex !== "number" || !Number.isInteger(data.lineIndex) || data.lineIndex < 0) invalid("lineIndex must be a non-negative integer.");
  const lineIndex = data.lineIndex as number;
  const proposedProductId = requireNonEmptyString(data.proposedProductId, "proposedProductId");
  const proposedQuantity = requirePositiveInt(data.proposedQuantity, "proposedQuantity");
  const selectedModifiers = Array.isArray(data.proposedModifiers) ? data.proposedModifiers : [];
  const reasonCode = requireNonEmptyString(data.reasonCode, "reasonCode");
  const reasonMessage = requireNonEmptyString(data.reasonMessage, "reasonMessage");

  requireStaffPermission(request, organizationId, "manageDineInOrders");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const orderRef = db.collection("orders").doc(orderId);
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) throw new HttpsError("not-found", "Order not found.");
    const order = orderSnap.data()!;
    if (order.organizationId !== organizationId || order.branchId !== branchId) throw new HttpsError("not-found", "Order not found.");
    if (order.mode === "staffEntry") {
      throw new HttpsError("failed-precondition", "A staff-entered order's lines are already accepted — no replacement proposal is possible.");
    }
    const lines = [...(order.lines ?? [])] as Array<Record<string, unknown>>;
    if (lineIndex >= lines.length) throw new HttpsError("invalid-argument", "lineIndex is out of range.");
    const originalLine = lines[lineIndex];
    if (originalLine.status !== "pendingApproval") {
      throw new HttpsError("failed-precondition", `Line ${lineIndex} is not pendingApproval (current status: ${originalLine.status}) — only a still-undecided line may receive a replacement proposal.`);
    }

    const policy = await loadCanonicalChannelPricingPolicy(db, order.restaurantId as string, tx);
    const rawItem: RawProductItem = { kind: "product", productId: proposedProductId, quantity: proposedQuantity, selectedModifiers, note: "" };
    const proposedLine = await buildProductLine(db, rawItem, { restaurantId: order.restaurantId as string }, DINE_IN_COMMERCIAL_CHANNEL, policy, tx);

    const originalLineValue = computeLineValueMinorUnits(originalLine as { quantity: number; unitPrice?: { minorUnits: number }; lineDiscount?: { minorUnits: number }; modifiers?: Array<{ unitExtraPrice?: { minorUnits: number }; quantity: number }> });
    const proposedLineTotalMinorUnits = (proposedLine.unitPriceMinorUnits + proposedLine.modifierTotalMinorUnits) * proposedLine.quantity - proposedLine.lineDiscountMinorUnits;

    const now = Timestamp.now();
    const priorProposalVersion = ((originalLine.counterProposal as CounterProposalSnapshot | null)?.proposalVersion ?? 0);
    const snapshot: CounterProposalSnapshot = {
      proposalVersion: priorProposalVersion + 1,
      proposedProductId, proposedProductName: proposedLine.productName,
      proposedModifiers: proposedLine.modifiers.map((m) => ({
        groupId: m.groupId, groupName: m.groupName, optionId: m.optionId, optionName: m.optionName,
        unitExtraPrice: { minorUnits: m.unitExtraPriceMinorUnits, currencyCode: "TRY" }, quantity: m.quantity,
      })),
      proposedQuantity, proposedUnitPrice: { minorUnits: proposedLine.unitPriceMinorUnits, currencyCode: "TRY" },
      proposedLineTotalMinorUnits, differenceFromOriginalMinorUnits: proposedLineTotalMinorUnits - originalLineValue,
      reasonCode, reasonMessage, proposedByStaffUid: request.auth!.uid,
      createdAt: now, expiresAt: Timestamp.fromMillis(now.toMillis() + COUNTER_PROPOSAL_TTL_MINUTES * 60_000),
      status: "pendingCustomerResponse", respondedAt: null,
    };

    lines[lineIndex] = { ...originalLine, status: "proposedChange", counterProposal: snapshot };
    const earliest = computeEarliestPendingProposalExpiresAt(lines);
    tx.update(orderRef, { lines, hasPendingProposal: earliest !== null, earliestPendingProposalExpiresAt: earliest });

    writeAuditEvent({
      tx, db, eventId: `${orderId}_${lineIndex}-proposed-${now.toMillis()}`,
      organizationId, branchId, type: "orderLine.replacementProposed", targetRef: orderRef.path,
      newValue: { lineIndex, proposedProductId, proposedQuantity, differenceFromOriginalMinorUnits: snapshot.differenceFromOriginalMinorUnits },
      actorType: "staff", actorUid: request.auth!.uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });

    return { orderId, lineIndex, proposalVersion: snapshot.proposalVersion, expiresAt: snapshot.expiresAt.toDate().toISOString() };
  });
});

export const respondToDineInCounterProposal = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const orderId = requireNonEmptyString(data.orderId, "orderId");
  if (typeof data.lineIndex !== "number" || !Number.isInteger(data.lineIndex) || data.lineIndex < 0) invalid("lineIndex must be a non-negative integer.");
  const lineIndex = data.lineIndex as number;
  const decision = data.decision;
  if (decision !== "accept" && decision !== "reject") invalid('decision must be "accept" or "reject".');

  const db = getFirestore();
  const uid = request.auth.uid;
  return db.runTransaction(async (tx) => {
    const orderRef = db.collection("orders").doc(orderId);
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) throw new HttpsError("not-found", "Order not found.");
    const order = orderSnap.data()!;

    // Customer owner ONLY — either the real customerId or the anonymous guestAuthUid.
    const isOwner = order.customerId === uid || order.guestAuthUid === uid;
    if (!isOwner) throw new HttpsError("permission-denied", "Only the order's own owner may respond to a replacement proposal.");

    const lines = [...(order.lines ?? [])] as Array<Record<string, unknown>>;
    if (lineIndex >= lines.length) throw new HttpsError("invalid-argument", "lineIndex is out of range.");
    const line = lines[lineIndex];
    const proposal = line.counterProposal as CounterProposalSnapshot | null;
    // Deliberately NOT also gated on `line.status === "proposedChange"` here
    // — once a proposal is resolved, `line.status` moves on to
    // `accepted`/`rejected` while `counterProposal` itself still holds the
    // historical record. Gating on line.status here would make the
    // idempotent-replay check below unreachable for every already-resolved
    // proposal, which is exactly the case it exists to handle.
    if (!proposal) {
      throw new HttpsError("failed-precondition", "This line has no replacement proposal.");
    }

    const now = Timestamp.now();
    // Idempotent replay — same decision already recorded: safe no-op.
    if (proposal.status === (decision === "accept" ? "accepted" : "rejected")) {
      return { orderId, lineIndex, status: proposal.status, idempotent: true };
    }
    if (proposal.status !== "pendingCustomerResponse") {
      throw new HttpsError("failed-precondition", `This proposal is already "${proposal.status}" — a conflicting second response is rejected.`);
    }
    if (proposal.expiresAt.toMillis() < now.toMillis()) {
      lines[lineIndex] = { ...line, status: "rejected", counterProposal: { ...proposal, status: "expired", respondedAt: now } };
      tx.update(orderRef, { lines, hasPendingProposal: false, earliestPendingProposalExpiresAt: computeEarliestPendingProposalExpiresAt(lines) });
      throw new HttpsError("failed-precondition", "This proposal has expired — ask staff for a fresh one.", { code: "proposal/expired" });
    }

    if (decision === "reject") {
      lines[lineIndex] = { ...line, status: "rejected", counterProposal: { ...proposal, status: "rejected", respondedAt: now } };
    } else {
      // Stale catalog/availability re-check — never silently substitute a
      // different price/product than what the customer actually saw.
      const productSnap = await loadCanonicalMenuProduct(db, proposal.proposedProductId, tx);
      if (!productSnap || productSnap.isAvailable !== true) {
        throw new HttpsError("failed-precondition", "The proposed product is no longer available — ask staff for a fresh proposal.", { code: "proposal/stale" });
      }
      // Accept EXACTLY the snapshotted values — never a freshly-recomputed price.
      lines[lineIndex] = {
        ...line,
        status: "accepted",
        productId: proposal.proposedProductId,
        productName: proposal.proposedProductName,
        modifiers: proposal.proposedModifiers,
        quantity: proposal.proposedQuantity,
        unitPrice: proposal.proposedUnitPrice,
        counterProposal: { ...proposal, status: "accepted", respondedAt: now },
      };
    }

    const stillPending = lines.some((l) => l.status === "pendingApproval");
    const anyResolved = lines.some((l) => l.status === "accepted" || l.status === "rejected");
    const linesDispositionSummary = stillPending ? (anyResolved ? "partiallyResolved" : "pending") : "resolved";
    tx.update(orderRef, {
      lines, linesDispositionSummary,
      hasPendingProposal: computeEarliestPendingProposalExpiresAt(lines) !== null,
      earliestPendingProposalExpiresAt: computeEarliestPendingProposalExpiresAt(lines),
    });

    writeAuditEvent({
      tx, db, eventId: `${orderId}_${lineIndex}-proposalResponse-${now.toMillis()}`,
      organizationId: order.organizationId, branchId: order.branchId,
      type: decision === "accept" ? "orderLine.replacementAccepted" : "orderLine.replacementRejected",
      targetRef: orderRef.path, newValue: { lineIndex },
      actorType: "customer", actorUid: uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });

    return { orderId, lineIndex, status: decision === "accept" ? "accepted" : "rejected", idempotent: false };
  });
});

/** Mirrors `reservationSweep.ts`/`sweepExpiredApprovalRequests`'s own real, tested sweep-function precedent — callable directly or wired to Cloud Scheduler later. */
export const sweepExpiredDineInCounterProposals = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async () => {
  const db = getFirestore();
  const now = Timestamp.now();
  const candidatesSnap = await db.collection("orders")
    .where("hasPendingProposal", "==", true)
    .where("earliestPendingProposalExpiresAt", "<=", now)
    .get();

  let expiredCount = 0;
  for (const doc of candidatesSnap.docs) {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(doc.ref);
      if (!snap.exists) return;
      const order = snap.data()!;
      const lines = [...(order.lines ?? [])] as Array<Record<string, unknown>>;
      let changed = false;
      for (let i = 0; i < lines.length; i++) {
        const proposal = lines[i].counterProposal as CounterProposalSnapshot | null;
        if (!proposal || proposal.status !== "pendingCustomerResponse" || proposal.expiresAt.toMillis() > now.toMillis()) continue;
        lines[i] = { ...lines[i], status: "rejected", counterProposal: { ...proposal, status: "expired", respondedAt: now } };
        changed = true;
      }
      if (!changed) return;
      const stillPending = lines.some((l) => l.status === "pendingApproval");
      const anyResolved = lines.some((l) => l.status === "accepted" || l.status === "rejected");
      tx.update(doc.ref, {
        lines,
        linesDispositionSummary: stillPending ? (anyResolved ? "partiallyResolved" : "pending") : "resolved",
        hasPendingProposal: computeEarliestPendingProposalExpiresAt(lines) !== null,
        earliestPendingProposalExpiresAt: computeEarliestPendingProposalExpiresAt(lines),
      });
      expiredCount += 1;
    });
  }
  return { expiredCount };
});
