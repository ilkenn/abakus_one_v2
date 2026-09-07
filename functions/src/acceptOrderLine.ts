import { HttpsError } from "firebase-functions/v2/https";
import type { Timestamp, Transaction, Firestore } from "firebase-admin/firestore";

/**
 * `enqueueKitchenWorkAndConsumeStock` — AP-5 Sprint 2.
 *
 * Split into `prepareKitchenWorkAndStockConsumption` (reads only) and
 * `applyKitchenWorkAndStockConsumption` (writes only, from the prepared
 * plan) — **required** by Firestore's own transaction discipline ("every
 * `tx.get()` must happen before the transaction's first write"), which
 * `submitDineInOrder.ts` already documents and follows explicitly. The
 * original single-function design broke exactly this rule: called after
 * the enclosing transaction's own earlier writes
 * (`applyTakeawayLifecycleTransition`, `tx.update(orderRef, ...)`,
 * `tx.set(orderRef, buildDineInOrderDocument(...))`), its own internal
 * `tx.get()` calls threw, silently aborting the whole transaction —
 * caught by `takeawayOrderLifecycle.test.ts`'s existing regression suite,
 * not assumed away.
 *
 * Each of the four real acceptance call sites (`submitDineInOrder.ts`
 * staffEntry create, `respondToDineInOrderLines.ts` accept,
 * `respondToTakeawayOrder.ts`/`respondToDeliveryOrder.ts` confirm) calls
 * `prepare...` as early as possible — before its own first write — and
 * `apply...` afterward (write-after-write ordering is unrestricted).
 *
 * Ports, server-side: `EnqueueKitchenWorkItems` + `KitchenRoutingResolver`
 * (kitchen enqueue), `ConsumeStockForOrder` + `RecordStockMovement`
 * (stock deduction, including the `NegativeStockPolicy` check). See
 * `RecipeIngredientLinkLine`'s own Dart doc comment for why this reads an
 * already-flattened ingredient list from `recipeIngredientLinks` rather
 * than re-flattening a live `RecipeVersion` (no real Firestore data exists
 * for one yet).
 *
 * **Idempotent per accepted line**: key `accept-${orderId}-${orderLineId}`
 * against `stockConsumptionRecords` — a duplicate call for an
 * already-processed line skips *both* kitchen enqueue and stock
 * consumption together for that line, never just one half.
 *
 * **Negative-stock policy**: read from `inventoryItems/{id}
 * .negativeStockPolicy` if that document exists; **defaults to `forbid`
 * when it doesn't** (no real `inventoryItems` writer exists yet either —
 * `forbid` mirrors `InventoryItem`'s own Dart constructor default
 * exactly, the safe choice when unconfigured, never a silent `allow`).
 * `forbid` throws from the *prepare* phase, before any write in either
 * this plan or the enclosing transaction has been queued for THIS
 * function's own work — the enclosing transaction as a whole still only
 * commits if every other write it queues succeeds too, but this function
 * itself never queues a partial plan.
 */

export interface AcceptedLine {
  orderLineId: string;
  productId: string;
  quantity: number;
}

export interface PrepareKitchenWorkAndStockConsumptionParams {
  tx: Transaction;
  db: Firestore;
  organizationId: string;
  branchId: string;
  orderId: string;
  channel: string;
  acceptedLines: AcceptedLine[];
  performedByUid: string;
  now: Timestamp;
}

interface StockLine {
  inventoryItemId: string;
  quantitySmallestUnits: number;
  unitCode: string;
  orderLineId: string;
  kind: "ingredient" | "packaging";
}

interface FirestoreWrite {
  collection: string;
  id: string;
  data: Record<string, unknown>;
}

export interface KitchenWorkAndStockConsumptionPlan {
  writes: FirestoreWrite[];
}

function stationForLine(
  routingRuleDocs: FirebaseFirestore.QueryDocumentSnapshot[],
): string {
  // V1 default: single `shared` station (architecture doc §13) — no
  // dynamic rule-matching ported server-side this sprint (no real
  // `KitchenRoutingRule` writer exists yet either); every rule document,
  // if any ever exist, is currently ignored in favor of the same default
  // the client resolver already applies when no rule matches.
  void routingRuleDocs;
  return "shared";
}

/** Read phase only — must be called before the enclosing transaction's
 * first write. Returns `null` when every accepted line was already
 * processed (fully idempotent no-op — nothing for `apply` to do). */
export async function prepareKitchenWorkAndStockConsumption(
  params: PrepareKitchenWorkAndStockConsumptionParams,
): Promise<KitchenWorkAndStockConsumptionPlan | null> {
  const { tx, db, organizationId, branchId, orderId, channel, acceptedLines, performedByUid, now } = params;
  if (acceptedLines.length === 0) return null;

  const recordRefs = acceptedLines.map((line) =>
    db.collection("stockConsumptionRecords").doc(`accept-${orderId}-${line.orderLineId}`),
  );
  const recordSnaps = await Promise.all(recordRefs.map((ref) => tx.get(ref)));
  const pendingLines = acceptedLines.filter((_, i) => !recordSnaps[i].exists);
  if (pendingLines.length === 0) return null; // Every line already processed.

  const routingRulesSnap = await tx.get(
    db.collection("kitchenRoutingRules").where("branchId", "==", branchId),
  );

  const recipeLinkRefs = pendingLines.map((l) =>
    db.collection("recipeIngredientLinks").doc(`link-${l.productId}`),
  );
  const recipeLinkSnaps = await Promise.all(recipeLinkRefs.map((ref) => tx.get(ref)));

  const packagingLinkRefs = pendingLines.map((l) =>
    db.collection("productPackagingLinks").doc(`link-${l.productId}-${channel}`),
  );
  const packagingLinkSnaps = await Promise.all(packagingLinkRefs.map((ref) => tx.get(ref)));

  const stockLines: StockLine[] = [];
  pendingLines.forEach((line, i) => {
    const recipeLink = recipeLinkSnaps[i];
    if (recipeLink.exists) {
      const ingredients = (recipeLink.data()!.ingredients ?? []) as Array<{
        inventoryItemId: string;
        quantitySmallestUnits: number;
        unitCode: string;
      }>;
      for (const ingredient of ingredients) {
        stockLines.push({
          inventoryItemId: ingredient.inventoryItemId,
          quantitySmallestUnits: ingredient.quantitySmallestUnits * line.quantity,
          unitCode: ingredient.unitCode,
          orderLineId: line.orderLineId,
          kind: "ingredient",
        });
      }
    }
    const packagingLink = packagingLinkSnaps[i];
    if (packagingLink.exists) {
      const data = packagingLink.data()!;
      stockLines.push({
        inventoryItemId: data.packagingInventoryItemId as string,
        quantitySmallestUnits: (data.quantity as number) * line.quantity,
        unitCode: (data.unitCode as string) ?? "piece",
        orderLineId: line.orderLineId,
        kind: "packaging",
      });
    }
  });

  const distinctInventoryItemIds = [...new Set(stockLines.map((l) => l.inventoryItemId))];
  const inventoryItemRefs = distinctInventoryItemIds.map((id) => db.collection("inventoryItems").doc(id));
  const inventoryItemSnaps = await Promise.all(inventoryItemRefs.map((ref) => tx.get(ref)));
  const policyByItemId = new Map<string, "forbid" | "warn" | "allow">();
  distinctInventoryItemIds.forEach((id, i) => {
    const snap = inventoryItemSnaps[i];
    const policy = snap.exists ? (snap.data()!.negativeStockPolicy as string) : "forbid";
    policyByItemId.set(id, (policy === "warn" || policy === "allow" ? policy : "forbid"));
  });

  const branchStockRefs = distinctInventoryItemIds.map((id) =>
    db.collection("branchStock").doc(`${branchId}_${id}`),
  );
  const branchStockSnaps = await Promise.all(branchStockRefs.map((ref) => tx.get(ref)));
  const runningBalance = new Map<string, number>();
  distinctInventoryItemIds.forEach((id, i) => {
    const snap = branchStockSnaps[i];
    runningBalance.set(id, snap.exists ? (snap.data()!.quantityOnHand as number) : 0);
  });
  const warningByItemId = new Map<string, boolean>();

  // Validate — a `forbid` violation throws here, in the read phase,
  // before this function queues any write of its own.
  for (const stockLine of stockLines) {
    const current = runningBalance.get(stockLine.inventoryItemId)!;
    const next = current - stockLine.quantitySmallestUnits;
    if (next < 0) {
      const policy = policyByItemId.get(stockLine.inventoryItemId)!;
      if (policy === "forbid") {
        throw new HttpsError(
          "failed-precondition",
          `Insufficient stock for "${stockLine.inventoryItemId}" — negative stock is not allowed for this item.`,
        );
      }
      if (policy === "warn") {
        warningByItemId.set(stockLine.inventoryItemId, true);
      }
    }
    runningBalance.set(stockLine.inventoryItemId, next);
  }

  const writes: FirestoreWrite[] = [];

  for (const line of pendingLines) {
    writes.push({
      collection: "kitchenWorkItems",
      id: `kwi-${line.orderLineId}`,
      data: {
        organizationId,
        branchId,
        station: stationForLine(routingRulesSnap.docs),
        orderId,
        kitchenTicketId: `kt-${orderId}`,
        kitchenTicketLineId: line.orderLineId,
        quantity: line.quantity,
        readyQuantity: 0,
        status: "queued",
        queuedAt: now,
        revision: 1,
        idempotencyKey: `kt-${orderId}-${line.orderLineId}`,
      },
    });
  }

  for (const id of distinctInventoryItemIds) {
    writes.push({
      collection: "branchStock",
      id: `${branchId}_${id}`,
      data: {
        inventoryItemId: id,
        branchId,
        locationId: branchId,
        quantityOnHand: runningBalance.get(id)!,
        isNegativeStockWarning: warningByItemId.get(id) ?? false,
        updatedAt: now,
      },
    });
  }

  stockLines.forEach((stockLine, index) => {
    writes.push({
      collection: "stockMovements",
      id: `move-${orderId}-${stockLine.orderLineId}-${stockLine.inventoryItemId}-${index}`,
      data: {
        organizationId,
        branchId,
        inventoryItemId: stockLine.inventoryItemId,
        locationId: branchId,
        type: "consumption",
        quantityDeltaSmallestUnits: -stockLine.quantitySmallestUnits,
        unitCode: stockLine.unitCode,
        relatedOrderId: orderId,
        correlationId: stockLine.orderLineId,
        performedByUid,
        occurredAt: now,
        idempotencyKey: `accept-${orderId}-${stockLine.orderLineId}-${stockLine.inventoryItemId}`,
      },
    });
  });

  for (const line of pendingLines) {
    writes.push({
      collection: "stockConsumptionRecords",
      id: `accept-${orderId}-${line.orderLineId}`,
      data: {
        organizationId,
        branchId,
        orderId,
        orderLineId: line.orderLineId,
        productId: line.productId,
        consumedAt: now,
        // AP-5 Sprint 3 — `cancelOrderLineStock.ts` reads this to decide
        // whether a cancellation should reverse (still `consumed`) or is a
        // stale no-op (already `reversed`/`wasted`).
        disposition: "consumed",
      },
    });
  }

  return { writes };
}

/** Write phase only — no reads. Safe to call anywhere after `prepare...`
 * within the same transaction, regardless of what other writes the
 * enclosing transaction has already queued. */
export function applyKitchenWorkAndStockConsumption(
  tx: Transaction,
  db: Firestore,
  plan: KitchenWorkAndStockConsumptionPlan | null,
): void {
  if (!plan) return;
  for (const write of plan.writes) {
    tx.set(db.collection(write.collection).doc(write.id), write.data);
  }
}
