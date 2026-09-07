import { HttpsError } from "firebase-functions/v2/https";
import type { ActionHandlerParams, ActionHandlerResult } from "./remoteApproval";

/**
 * `stockCountEngine.ts` — AP-5 Sprint 3. Mirrors `cashRegisterEngine.ts`'s
 * naming/shape: the `remoteApprovalRequests`-side approve/reject handlers
 * for `stockCountAdjustment`, ported from the real, already-tested Dart
 * `ApproveStockCount`
 * (`lib/features/inventory/application/use_cases/approve_stock_count.dart`)
 * — same `StockMovementType.countCorrection` type, same "rejecting never
 * touches stock at all" contract. Re-routed through AP-4's async,
 * cross-device `remoteApprovalRequests` mechanism instead of that Dart use
 * case's direct-call shape, per the governing spec — self-approval is
 * already prevented structurally by `respondToApprovalRequest` itself
 * (the requester can never respond to their own request), so this handler
 * doesn't re-check it.
 */

interface StockCountDoc {
  organizationId: string;
  branchId: string;
  locationId: string;
  status: "inProgress" | "submitted" | "approved" | "rejected";
}

interface StockCountLineDoc {
  countId: string;
  inventoryItemId: string;
  unitCode: string;
  expectedQuantitySmallestUnits: number;
  countedQuantitySmallestUnits: number;
  varianceSmallestUnits: number;
}

export async function applyStockCountAdjustment(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now, respondedByActorUid } = params;
  const countRef = db.doc(approval.targetAggregateRef);
  const countSnap = await tx.get(countRef);
  if (!countSnap.exists) {
    throw new HttpsError("not-found", "The stock count no longer exists.");
  }
  const count = countSnap.data() as StockCountDoc;
  if (count.status !== "submitted") {
    throw new HttpsError("failed-precondition", `Stock count is already "${count.status}".`);
  }

  const linesSnap = await tx.get(db.collection("stockCountLines").where("countId", "==", countRef.id));
  const lines = linesSnap.docs.map((doc) => doc.data() as StockCountLineDoc);
  const nonZeroLines = lines.filter((line) => line.varianceSmallestUnits !== 0);

  const branchStockRefs = nonZeroLines.map((line) =>
    db.collection("branchStock").doc(`${count.branchId}_${line.inventoryItemId}`),
  );
  const branchStockSnaps = await Promise.all(branchStockRefs.map((ref) => tx.get(ref)));

  // --- writes ---
  nonZeroLines.forEach((line, index) => {
    const existing = branchStockSnaps[index];
    const beforeQuantity = existing.exists ? (existing.data()!.quantityOnHand as number) : 0;

    tx.set(db.collection("stockMovements").doc(), {
      organizationId: count.organizationId,
      branchId: count.branchId,
      inventoryItemId: line.inventoryItemId,
      locationId: count.locationId,
      type: "countCorrection",
      quantityDeltaSmallestUnits: line.varianceSmallestUnits,
      unitCode: line.unitCode,
      relatedOrderId: null,
      correlationId: countRef.id,
      performedByUid: respondedByActorUid,
      occurredAt: now,
      idempotencyKey: `stock-count-${countRef.id}-${line.inventoryItemId}`,
    });

    tx.set(
      db.collection("branchStock").doc(`${count.branchId}_${line.inventoryItemId}`),
      {
        inventoryItemId: line.inventoryItemId,
        branchId: count.branchId,
        locationId: count.locationId,
        quantityOnHand: line.countedQuantitySmallestUnits,
        updatedAt: now,
      },
      { merge: true },
    );

    tx.set(db.collection("inventoryAuditEntries").doc(), {
      organizationId: count.organizationId,
      branchId: count.branchId,
      actorId: respondedByActorUid,
      type: "stockCountApproved",
      description: `Stock count "${countRef.id}" approved: ${line.inventoryItemId} ${beforeQuantity} -> ${line.countedQuantitySmallestUnits} ${line.unitCode}`,
      targetEntityId: countRef.id,
      beforeQuantitySmallestUnits: beforeQuantity,
      afterQuantitySmallestUnits: line.countedQuantitySmallestUnits,
      timestamp: now,
    });
  });

  tx.update(countRef, { status: "approved", approvedByStaffId: respondedByActorUid, approvedAt: now });

  return { newValue: { countId: countRef.id, status: "approved", correctedLineCount: nonZeroLines.length } };
}

export async function applyStockCountAdjustmentRejected(
  params: ActionHandlerParams,
): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now, respondedByActorUid } = params;
  const countRef = db.doc(approval.targetAggregateRef);
  const countSnap = await tx.get(countRef);
  if (!countSnap.exists) {
    throw new HttpsError("not-found", "The stock count no longer exists.");
  }
  const count = countSnap.data() as StockCountDoc;
  if (count.status !== "submitted") {
    throw new HttpsError("failed-precondition", `Stock count is already "${count.status}".`);
  }

  // Rejecting touches no stock at all — matches `ApproveStockCount`'s own
  // exact contract.
  tx.update(countRef, {
    status: "rejected",
    approvedByStaffId: respondedByActorUid,
    approvedAt: now,
  });

  tx.set(db.collection("inventoryAuditEntries").doc(), {
    organizationId: count.organizationId,
    branchId: count.branchId,
    actorId: respondedByActorUid,
    type: "stockCountRejected",
    description: `Stock count "${countRef.id}" rejected`,
    targetEntityId: countRef.id,
    timestamp: now,
  });

  return { newValue: { countId: countRef.id, status: "rejected" } };
}
