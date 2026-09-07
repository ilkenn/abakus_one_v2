import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission } from "./staffAuthorization";

/**
 * `setProductPackagingLink` — AP-5 Sprint 2.
 *
 * The real, manager-tier writer for `productPackagingLinks` — which
 * packaging `InventoryItem` a product consumes on acceptance for a given
 * sales channel (`channelCode` free-text, mirrors `StockConsumptionChannelPolicy`'s
 * own established reason for not importing `OrderChannel`). One document
 * per `(productId, channelCode)` pair (deterministic id
 * `link-${productId}-${channelCode}`), upserted, `revision` increments per
 * edit — same "current binding, not a history collection" shape as
 * `setRecipeIngredientLink`.
 *
 * **No existence validation against a real `inventoryItems` document**:
 * same disclosed limitation as `setRecipeIngredientLink` — `ingredients`/
 * `inventoryItems` have no real Cloud Function writer yet either.
 */

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  return raw;
}

function requirePositiveInt(raw: unknown, field: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 1) {
    throw new HttpsError("invalid-argument", `${field} must be a positive integer.`);
  }
  return raw;
}

export const setProductPackagingLink = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const productId = requireString(data.productId, "productId");
    const channelCode = requireString(data.channelCode, "channelCode");
    const packagingInventoryItemId = requireString(
      data.packagingInventoryItemId,
      "packagingInventoryItemId",
    );
    const quantity = requirePositiveInt(data.quantity, "quantity");

    requireStaffPermission(request, organizationId, "manageInventory");

    const db = getFirestore();
    const linkRef = db
      .collection("productPackagingLinks")
      .doc(`link-${productId}-${channelCode}`);

    return db.runTransaction(async (tx) => {
      const existing = await tx.get(linkRef);
      const now = Timestamp.now();
      const revision = existing.exists ? ((existing.data()!.revision as number) + 1) : 1;

      tx.set(linkRef, {
        organizationId,
        productId,
        channelCode,
        packagingInventoryItemId,
        quantity,
        createdAt: existing.exists ? existing.data()!.createdAt : now,
        updatedAt: now,
        revision,
      });

      return { linkId: linkRef.id, revision };
    });
  },
);
