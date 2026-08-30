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
import { vatAmountOf } from "./takeawayMoney";

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
  // ISO 8601 strings, not native Firestore `Timestamp`s — matching every
  // other date field on this same order document (`OrderTimestamps`, etc.),
  // which `order_firestore_mapper.dart`'s `DateTime.parse(x as String)`
  // convention already relies on everywhere else. Storing these three as
  // native `Timestamp`s (as an earlier version of this file did) was a
  // real, previously-undiscovered bug: the customer-facing counter-proposal
  // UI (`DineInLineApprovalSection`) silently rendered nothing at all for
  // every real proposal ever created, because its `AsyncValue.error` branch
  // swallows the resulting `TypeError` without surfacing it anywhere —
  // found only by driving the real customer screen end to end (AP-3 wave
  // 7). The denormalized top-level `earliestPendingProposalExpiresAt`
  // field is unaffected by this fix — it stays a native `Timestamp`
  // deliberately, since it is the one field of the two actually queried on
  // (`sweepExpiredDineInCounterProposals` below), and no Dart client ever
  // reads it directly.
  createdAt: string;
  expiresAt: string;
  status: "pendingCustomerResponse" | "accepted" | "rejected" | "expired";
  respondedAt: string | null;
}

/** Recomputes the order's earliest-still-pending-proposal expiry across every line — the denormalized top-level field the sweep queries on (nested-array Firestore queries aren't possible; mirrors this codebase's own established denormalize-for-queryability convention). Returns a native `Timestamp` (unlike the per-line `counterProposal.expiresAt` ISO strings this reads from) because this is the one value actually used in a Firestore range query. */
function computeEarliestPendingProposalExpiresAt(lines: Array<Record<string, unknown>>): Timestamp | null {
  let earliestMillis: number | null = null;
  for (const line of lines) {
    const proposal = line.counterProposal as CounterProposalSnapshot | null | undefined;
    if (!proposal || proposal.status !== "pendingCustomerResponse") continue;
    const millis = new Date(proposal.expiresAt).getTime();
    if (earliestMillis === null || millis < earliestMillis) earliestMillis = millis;
  }
  return earliestMillis === null ? null : Timestamp.fromMillis(earliestMillis);
}

/**
 * AP-3 wave 7 correction — a real, previously-undiscovered gap: accepting a
 * counter-proposal updated the affected LINE's `productId`/`unitPrice`
 * correctly, but nothing ever recomputed the order-level `pricing`
 * aggregate (`grossSubtotal`/`taxableBase`/`vatAmount`/`grandTotal`) from
 * the now-changed lines — so a customer who accepted a cheaper or pricier
 * replacement would see the ORIGINAL total forever, not just transiently.
 * Reuses `computeLineValueMinorUnits` (the same per-line total this file
 * already uses for `differenceFromOriginalMinorUnits`) and `vatAmountOf`
 * (the same VAT helper `submitTakeawayOrder.ts`'s canonical `buildOrderLine`
 * uses) — never a hand-rolled formula. `serviceFee`/`deliveryFee`/
 * `packagingFee`/`tip`/`discount` are untouched (a counter-proposal never
 * touches loyalty/campaign/delivery state), matching `grandTotal =
 * grossSubtotal - discount` exactly like every other channel's pricing
 * pipeline. Called on every non-expired response (accept AND reject) —
 * reject leaves every line's price unchanged, so the recompute is a
 * mathematical no-op there, but running it unconditionally means `pricing`
 * is always freshly derived from `lines`, never silently allowed to drift.
 */
function recomputeOrderPricing(
  lines: Array<Record<string, unknown>>,
  priorPricing: Record<string, unknown>,
): Record<string, unknown> {
  let grossSubtotalMinorUnits = 0;
  let taxableBaseMinorUnits = 0;
  let vatAmountMinorUnits = 0;
  for (const line of lines) {
    const lineTotalMinorUnits = computeLineValueMinorUnits(line as {
      quantity: number;
      unitPrice?: { minorUnits: number };
      lineDiscount?: { minorUnits: number };
      modifiers?: Array<{ unitExtraPrice?: { minorUnits: number }; quantity: number }>;
    });
    const taxRateBasisPoints = (line.taxRateBasisPoints as number | undefined) ?? 0;
    const lineVatMinorUnits = vatAmountOf(lineTotalMinorUnits, taxRateBasisPoints);
    grossSubtotalMinorUnits += lineTotalMinorUnits;
    taxableBaseMinorUnits += lineTotalMinorUnits - lineVatMinorUnits;
    vatAmountMinorUnits += lineVatMinorUnits;
  }
  const currencyCode = ((priorPricing.grandTotal as { currencyCode?: string } | undefined)?.currencyCode) ?? "TRY";
  const discountMinorUnits = (priorPricing.discount as { minorUnits?: number } | undefined)?.minorUnits ?? 0;
  return {
    ...priorPricing,
    grossSubtotal: { minorUnits: grossSubtotalMinorUnits, currencyCode },
    taxableBase: { minorUnits: taxableBaseMinorUnits, currencyCode },
    vatAmount: { minorUnits: vatAmountMinorUnits, currencyCode },
    grandTotal: { minorUnits: grossSubtotalMinorUnits - discountMinorUnits, currencyCode },
  };
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
      createdAt: now.toDate().toISOString(),
      expiresAt: Timestamp.fromMillis(now.toMillis() + COUNTER_PROPOSAL_TTL_MINUTES * 60_000).toDate().toISOString(),
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

    return { orderId, lineIndex, proposalVersion: snapshot.proposalVersion, expiresAt: snapshot.expiresAt };
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
  // The expiry branch below must commit its "expired" write even though the
  // caller still needs to see a `failed-precondition`/`proposal/expired`
  // error — but a transaction callback that throws discards every `tx.*`
  // write it queued, Firestore rolls back the whole thing, not just the
  // parts after the throw. So the expiry case returns a plain sentinel
  // (never throws) to let the transaction commit, and the actual
  // `HttpsError` is thrown once, outside `runTransaction`, from that
  // sentinel — same "reflect real backend state before failing" reasoning
  // `sweepExpiredDineInCounterProposals` already established, just applied
  // to the inline check inside this callable instead of the sweep.
  const result = await db.runTransaction(async (tx) => {
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
      return { expired: false as const, orderId, lineIndex, status: proposal.status, idempotent: true };
    }
    if (proposal.status !== "pendingCustomerResponse") {
      throw new HttpsError("failed-precondition", `This proposal is already "${proposal.status}" — a conflicting second response is rejected.`);
    }
    if (new Date(proposal.expiresAt).getTime() < now.toMillis()) {
      lines[lineIndex] = { ...line, status: "rejected", counterProposal: { ...proposal, status: "expired", respondedAt: now.toDate().toISOString() } };
      tx.update(orderRef, { lines, hasPendingProposal: false, earliestPendingProposalExpiresAt: computeEarliestPendingProposalExpiresAt(lines) });
      return { expired: true as const };
    }

    if (decision === "reject") {
      lines[lineIndex] = { ...line, status: "rejected", counterProposal: { ...proposal, status: "rejected", respondedAt: now.toDate().toISOString() } };
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
        counterProposal: { ...proposal, status: "accepted", respondedAt: now.toDate().toISOString() },
      };
    }

    const stillPending = lines.some((l) => l.status === "pendingApproval");
    const anyResolved = lines.some((l) => l.status === "accepted" || l.status === "rejected");
    const linesDispositionSummary = stillPending ? (anyResolved ? "partiallyResolved" : "pending") : "resolved";
    const pricing = recomputeOrderPricing(lines, order.pricing as Record<string, unknown>);
    tx.update(orderRef, {
      lines, linesDispositionSummary, pricing,
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

    return { expired: false as const, orderId, lineIndex, status: decision === "accept" ? "accepted" : "rejected", idempotent: false };
  });

  if (result.expired) {
    throw new HttpsError("failed-precondition", "This proposal has expired — ask staff for a fresh one.", { code: "proposal/expired" });
  }
  return { orderId: result.orderId, lineIndex: result.lineIndex, status: result.status, idempotent: result.idempotent };
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
        if (!proposal || proposal.status !== "pendingCustomerResponse" || new Date(proposal.expiresAt).getTime() > now.toMillis()) continue;
        lines[i] = { ...lines[i], status: "rejected", counterProposal: { ...proposal, status: "expired", respondedAt: now.toDate().toISOString() } };
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
