import type { Timestamp, Transaction, Firestore } from "firebase-admin/firestore";

/**
 * `cancelOrderLineStock.ts` — AP-5 Sprint 3.
 *
 * The real consumer `applyAcceptedLineCancellation`'s own doc comment
 * (`checkFinancialAdjustments.ts`) already forecast: "AP-5's own future
 * consumer — this handler only produces the signal, never AP-5's stock/KDS
 * behavior itself." That handler's `preparationStarted` (order-level proxy)
 * is superseded here by the real per-line `kitchenWorkItems` status Sprint
 * 1/2 built.
 *
 * Same `prepare`/`apply` (read-then-write) split `acceptOrderLine.ts`
 * established in Sprint 2 — required for the same reason: called from
 * inside transactions (`applyAcceptedLineCancellation`,
 * `cancelTakeawayOrderForStaff`, `cancelDeliveryOrderForStaff`) that
 * already have earlier writes of their own queued.
 *
 * **Idempotent per line** — reuses the existing per-line
 * `stockConsumptionRecords/accept-{orderId}-{orderLineId}` doc (written at
 * acceptance, `acceptOrderLine.ts`) rather than a parallel ledger: only a
 * line whose record is still `disposition: 'consumed'` is processed; any
 * other value (or a missing record — nothing was ever consumed for that
 * line) is a safe no-op.
 *
 * **Reversal vs. waste, decided per line's real `kitchenWorkItem` status**:
 * - `queued`/`acknowledged` (not yet started) → **reversal**: increments
 *   `branchStock` back by exactly what was consumed, writes an offsetting
 *   `stockMovements` doc (`type: 'reversal'`), transitions the work item to
 *   `cancelled`.
 * - `preparing`/`ready` (already committed) → **waste**: does NOT touch
 *   `branchStock`/write a new `stockMovements` doc — the stock was already
 *   correctly reduced at acceptance; a second deduction would double-count.
 *   Writes one `wasteRecords` doc per originally-consumed item (ingredient
 *   AND packaging), transitions the work item to `wasted`.
 * - No `kitchenWorkItem` found (product had no recipe/packaging link, so
 *   nothing was ever consumed) → no stock/kitchen write at all, the
 *   idempotency record is simply closed out.
 * - Work item already in some OTHER terminal status (e.g. `unavailable`,
 *   set independently by kitchen staff) → left untouched; only the
 *   idempotency record is closed out, never a forced transition away from
 *   a status this module didn't itself set.
 */

export interface CancelOrderLineStockParams {
  tx: Transaction;
  db: Firestore;
  organizationId: string;
  branchId: string;
  orderId: string;
  orderLineIds: string[];
  performedByUid: string;
  now: Timestamp;
}

interface FirestoreWrite {
  collection: string;
  id: string;
  data: Record<string, unknown>;
}

export interface CancellationStockPlan {
  writes: FirestoreWrite[];
}

interface ConsumedMovement {
  movementId: string;
  inventoryItemId: string;
  quantityDeltaSmallestUnits: number; // negative, as written at acceptance
  unitCode: string;
}

const REVERSIBLE_STATUSES = new Set(["queued", "acknowledged"]);
const WASTE_STATUSES = new Set(["preparing", "ready"]);

export async function prepareCancellationStockHandling(
  params: CancelOrderLineStockParams,
): Promise<CancellationStockPlan | null> {
  const { tx, db, organizationId, branchId, orderId, orderLineIds, performedByUid, now } = params;
  if (orderLineIds.length === 0) return null;

  // --- reads ---
  const recordRefs = orderLineIds.map((id) =>
    db.collection("stockConsumptionRecords").doc(`accept-${orderId}-${id}`),
  );
  const recordSnaps = await Promise.all(recordRefs.map((ref) => tx.get(ref)));

  const pendingLineIds = orderLineIds.filter(
    (_, i) => recordSnaps[i].exists && recordSnaps[i].data()!.disposition === "consumed",
  );
  if (pendingLineIds.length === 0) return null;

  const workItemRefs = pendingLineIds.map((id) => db.collection("kitchenWorkItems").doc(`kwi-${id}`));
  const workItemSnaps = await Promise.all(workItemRefs.map((ref) => tx.get(ref)));

  const movementQuerySnaps = await Promise.all(
    pendingLineIds.map((lineId) =>
      tx.get(
        db
          .collection("stockMovements")
          .where("relatedOrderId", "==", orderId)
          .where("correlationId", "==", lineId)
          .where("type", "==", "consumption"),
      ),
    ),
  );

  interface LinePlan {
    orderLineId: string;
    disposition: "reversed" | "wasted" | "closed";
    workItemId?: string;
    workItemRevision?: number;
    movements: ConsumedMovement[];
  }

  const linePlans: LinePlan[] = pendingLineIds.map((orderLineId, i) => {
    const movements: ConsumedMovement[] = movementQuerySnaps[i].docs.map((doc) => ({
      movementId: doc.id,
      inventoryItemId: doc.data().inventoryItemId as string,
      quantityDeltaSmallestUnits: doc.data().quantityDeltaSmallestUnits as number,
      unitCode: doc.data().unitCode as string,
    }));

    const workItemSnap = workItemSnaps[i];
    if (!workItemSnap.exists) {
      return { orderLineId, disposition: "closed", movements };
    }
    const status = workItemSnap.data()!.status as string;
    const revision = workItemSnap.data()!.revision as number;
    if (REVERSIBLE_STATUSES.has(status)) {
      return { orderLineId, disposition: "reversed", workItemId: workItemSnap.id, workItemRevision: revision, movements };
    }
    if (WASTE_STATUSES.has(status)) {
      return { orderLineId, disposition: "wasted", workItemId: workItemSnap.id, workItemRevision: revision, movements };
    }
    // Already some other terminal status this module didn't set — leave
    // the work item alone, just close out the idempotency record.
    return { orderLineId, disposition: "closed", movements };
  });

  // Distinct inventory items across every REVERSED line's movements —
  // read current branchStock once per item (aggregated, mirrors
  // acceptOrderLine.ts's own same-item-multiple-lines handling).
  const reversalItemIds = [
    ...new Set(
      linePlans
        .filter((l) => l.disposition === "reversed")
        .flatMap((l) => l.movements.map((m) => m.inventoryItemId)),
    ),
  ];
  const branchStockRefs = reversalItemIds.map((id) => db.collection("branchStock").doc(`${branchId}_${id}`));
  const branchStockSnaps = await Promise.all(branchStockRefs.map((ref) => tx.get(ref)));
  const runningBalance = new Map<string, number>();
  reversalItemIds.forEach((id, i) => {
    const snap = branchStockSnaps[i];
    runningBalance.set(id, snap.exists ? (snap.data()!.quantityOnHand as number) : 0);
  });

  // --- compute writes ---
  const writes: FirestoreWrite[] = [];

  for (const line of linePlans) {
    if (line.disposition === "reversed") {
      line.movements.forEach((movement, index) => {
        const returnedAmount = -movement.quantityDeltaSmallestUnits; // positive
        runningBalance.set(
          movement.inventoryItemId,
          (runningBalance.get(movement.inventoryItemId) ?? 0) + returnedAmount,
        );
        writes.push({
          collection: "stockMovements",
          id: `move-${orderId}-${line.orderLineId}-${movement.inventoryItemId}-reversal-${index}`,
          data: {
            organizationId,
            branchId,
            inventoryItemId: movement.inventoryItemId,
            locationId: branchId,
            type: "reversal",
            quantityDeltaSmallestUnits: returnedAmount,
            unitCode: movement.unitCode,
            relatedOrderId: orderId,
            correlationId: line.orderLineId,
            reversalOfMovementId: movement.movementId,
            performedByUid,
            occurredAt: now,
            idempotencyKey: `cancel-reversal-${orderId}-${line.orderLineId}-${movement.inventoryItemId}`,
          },
        });
      });
      writes.push({
        collection: "kitchenWorkItems",
        id: line.workItemId!,
        data: { status: "cancelled", cancelledAt: now, revision: line.workItemRevision! + 1 },
      });
    } else if (line.disposition === "wasted") {
      line.movements.forEach((movement, index) => {
        writes.push({
          collection: "wasteRecords",
          id: `waste-${orderId}-${line.orderLineId}-${movement.inventoryItemId}-${index}`,
          data: {
            organizationId,
            branchId,
            inventoryItemId: movement.inventoryItemId,
            quantitySmallestUnits: -movement.quantityDeltaSmallestUnits, // positive wasted amount
            unitCode: movement.unitCode,
            reason: "customer_cancellation_after_prep",
            relatedStockMovementId: movement.movementId,
            orderId,
            orderLineId: line.orderLineId,
            staffUid: performedByUid,
            timestamp: now,
          },
        });
      });
      writes.push({
        collection: "kitchenWorkItems",
        id: line.workItemId!,
        data: { status: "wasted", wastedAt: now, revision: line.workItemRevision! + 1 },
      });
    }

    writes.push({
      collection: "stockConsumptionRecords",
      id: `accept-${orderId}-${line.orderLineId}`,
      data: { disposition: line.disposition === "closed" ? "wasted" : line.disposition },
    });
  }

  for (const id of reversalItemIds) {
    writes.push({
      collection: "branchStock",
      id: `${branchId}_${id}`,
      data: { inventoryItemId: id, branchId, locationId: branchId, quantityOnHand: runningBalance.get(id)!, updatedAt: now },
    });
  }

  return { writes };
}

/** Write phase only — no reads. `merge: true` for `kitchenWorkItems`/
 * `stockConsumptionRecords` (partial field updates onto an existing
 * document); every other collection here is a fresh append-only doc. */
export function applyCancellationStockHandling(
  tx: Transaction,
  db: Firestore,
  plan: CancellationStockPlan | null,
): void {
  if (!plan) return;
  for (const write of plan.writes) {
    const isPartialUpdate = write.collection === "kitchenWorkItems" || write.collection === "stockConsumptionRecords";
    tx.set(db.collection(write.collection).doc(write.id), write.data, { merge: isPartialUpdate });
  }
}
