import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { createApprovalRequest } from "./remoteApproval";

/**
 * `submitStockCount` — AP-5 Sprint 3.
 *
 * Server-side port of the real, already-tested Dart `SubmitStockCount`
 * (`lib/features/inventory/application/use_cases/submit_stock_count.dart`)
 * — same `recordStockCount` staff-tier permission, same "recounts create
 * new records, never editable once submitted" contract
 * (`StockCount.status`, real Dart enum values `inProgress/submitted/
 * approved/rejected` used verbatim, not the differently-worded strings a
 * spec draft suggested).
 *
 * **Not multi-step like the Dart UI flow** (`StartStockCount` →
 * `AddStockCountLine` → `SubmitStockCount`) — one callable accepts the
 * whole counted-item list at once and goes straight to `submitted`
 * (or `approved`, see below), since there is no server-side draft UI this
 * sprint to justify the extra round trips.
 *
 * **Zero-discrepancy auto-completes**: if every counted line has zero
 * variance, the count is marked `approved` immediately — nothing to
 * reconcile, no `remoteApprovalRequests` entry created. Any non-zero
 * variance leaves the whole count `submitted` and creates a
 * `stockCountAdjustment` approval request (same `createApprovalRequest`
 * shape `requestAcceptedLineCancellation` already uses) — `branchStock`
 * is never touched directly by this callable, matching the explicit
 * requirement that a discrepancy must go through manager approval first.
 */

interface CountedItemInput {
  inventoryItemId: string;
  countedQuantitySmallestUnits: number;
  unitCode: string;
}

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  return raw;
}

function requireCountedItems(raw: unknown): CountedItemInput[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new HttpsError("invalid-argument", "countedItems must be a non-empty array.");
  }
  return raw.map((entry, index) => {
    if (typeof entry !== "object" || entry === null) {
      throw new HttpsError("invalid-argument", `countedItems[${index}] must be an object.`);
    }
    const value = entry as Record<string, unknown>;
    const inventoryItemId = requireString(value.inventoryItemId, `countedItems[${index}].inventoryItemId`);
    const unitCode = requireString(value.unitCode, `countedItems[${index}].unitCode`);
    if (
      typeof value.countedQuantitySmallestUnits !== "number" ||
      !Number.isInteger(value.countedQuantitySmallestUnits) ||
      value.countedQuantitySmallestUnits < 0
    ) {
      throw new HttpsError(
        "invalid-argument",
        `countedItems[${index}].countedQuantitySmallestUnits must be a non-negative integer.`,
      );
    }
    return { inventoryItemId, unitCode, countedQuantitySmallestUnits: value.countedQuantitySmallestUnits };
  });
}

export const submitStockCount = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const branchId = requireString(data.branchId, "branchId");
    const locationId = requireString(data.locationId, "locationId");
    const countedItems = requireCountedItems(data.countedItems);

    requireStaffPermission(request, organizationId, "recordStockCount");
    requireBranchAccess(request, organizationId, branchId);

    const db = getFirestore();

    // --- reads: current branchStock per counted item (all before any write) ---
    const branchStockRefs = countedItems.map((item) =>
      db.collection("branchStock").doc(`${branchId}_${item.inventoryItemId}`),
    );
    const branchStockSnaps = await Promise.all(branchStockRefs.map((ref) => ref.get()));

    const countRef = db.collection("stockCounts").doc();
    const now = Timestamp.now();

    const lines = countedItems.map((item, index) => {
      const snap = branchStockSnaps[index];
      const expectedQuantitySmallestUnits = snap.exists ? (snap.data()!.quantityOnHand as number) : 0;
      const varianceSmallestUnits = item.countedQuantitySmallestUnits - expectedQuantitySmallestUnits;
      return {
        lineRef: db.collection("stockCountLines").doc(),
        inventoryItemId: item.inventoryItemId,
        unitCode: item.unitCode,
        expectedQuantitySmallestUnits,
        countedQuantitySmallestUnits: item.countedQuantitySmallestUnits,
        varianceSmallestUnits,
      };
    });

    const hasDiscrepancy = lines.some((line) => line.varianceSmallestUnits !== 0);
    const status = hasDiscrepancy ? "submitted" : "approved";

    return db.runTransaction(async (tx) => {
      tx.set(countRef, {
        organizationId,
        branchId,
        locationId,
        status,
        startedByStaffId: request.auth!.uid,
        startedAt: now,
        submittedAt: now,
        approvedByStaffId: hasDiscrepancy ? null : request.auth!.uid,
        approvedAt: hasDiscrepancy ? null : now,
        rejectionReason: null,
      });

      for (const line of lines) {
        tx.set(line.lineRef, {
          countId: countRef.id,
          organizationId,
          branchId,
          inventoryItemId: line.inventoryItemId,
          unitCode: line.unitCode,
          expectedQuantitySmallestUnits: line.expectedQuantitySmallestUnits,
          countedQuantitySmallestUnits: line.countedQuantitySmallestUnits,
          varianceSmallestUnits: line.varianceSmallestUnits,
        });
      }

      let approvalRequestId: string | null = null;
      if (hasDiscrepancy) {
        const approval = await createApprovalRequest({
          organizationId,
          branchId,
          actionType: "stockCountAdjustment",
          requestedByActorUid: request.auth!.uid,
          targetAggregateRef: countRef.path,
          targetAggregateVersion: 1,
          payloadHash: countRef.id,
        });
        approvalRequestId = approval.requestId;
      }

      return { countId: countRef.id, status, approvalRequestId };
    });
  },
);
