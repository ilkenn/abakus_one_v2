import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission } from "./staffAuthorization";

/**
 * `setRecipeIngredientLink` — AP-5 Sprint 2.
 *
 * The real, manager-tier writer for `recipeIngredientLinks` — closing the
 * "no menu product currently references a recipe id at all" gap
 * (`ConsumeStockForOrder`'s own honest disclosure, `docs/
 * kds_printer_stock_architecture.md` §15). One document per `productId`
 * (deterministic id `link-${productId}`), upserted — `revision` increments
 * on every call so a correction is auditable, but this is a *current
 * binding* record, not itself a history collection: the historical
 * guarantee lives in `RecipeVersion` being immutable and in the caller of
 * `enqueueKitchenWorkAndConsumeStock` always resolving against the exact
 * `recipeVersionId` this link pointed to *at order-acceptance time*, never
 * a live re-read.
 *
 * **No existence validation against a real `recipeVersions` document, and
 * `ingredients` is a caller-supplied, already-flattened snapshot, not
 * server-recomputed**: `recipes`/`recipeVersions`/`subRecipes` have no
 * real Cloud Function writer yet (still entirely Dart in-memory, per the
 * Sprint 1 reuse-first audit) — there is no real Firestore document this
 * callable could read and flatten server-side. The caller (a manager
 * screen, once built) is responsible for supplying the already-flattened
 * result of the Dart `RecipeLineFlattener` for [recipeVersionId] — this is
 * what makes server-authoritative consumption possible at all this
 * sprint. Full nested sub-recipe recalculation server-side is out of
 * scope until `recipes`/`recipeVersions` get a real Firestore writer.
 */

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  return raw;
}

interface IngredientLine {
  inventoryItemId: string;
  quantitySmallestUnits: number;
  unitCode: string;
}

function requireIngredients(raw: unknown): IngredientLine[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new HttpsError("invalid-argument", "ingredients must be a non-empty array.");
  }
  return raw.map((entry, index) => {
    if (typeof entry !== "object" || entry === null) {
      throw new HttpsError("invalid-argument", `ingredients[${index}] must be an object.`);
    }
    const value = entry as Record<string, unknown>;
    const inventoryItemId = requireString(value.inventoryItemId, `ingredients[${index}].inventoryItemId`);
    const unitCode = requireString(value.unitCode, `ingredients[${index}].unitCode`);
    if (typeof value.quantitySmallestUnits !== "number" || !Number.isInteger(value.quantitySmallestUnits) || value.quantitySmallestUnits <= 0) {
      throw new HttpsError(
        "invalid-argument",
        `ingredients[${index}].quantitySmallestUnits must be a positive integer.`,
      );
    }
    return { inventoryItemId, unitCode, quantitySmallestUnits: value.quantitySmallestUnits };
  });
}

export const setRecipeIngredientLink = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const productId = requireString(data.productId, "productId");
    const recipeVersionId = requireString(data.recipeVersionId, "recipeVersionId");
    const ingredients = requireIngredients(data.ingredients);

    requireStaffPermission(request, organizationId, "manageRecipes");

    const db = getFirestore();
    const linkRef = db.collection("recipeIngredientLinks").doc(`link-${productId}`);

    return db.runTransaction(async (tx) => {
      const existing = await tx.get(linkRef);
      const now = Timestamp.now();
      const revision = existing.exists ? ((existing.data()!.revision as number) + 1) : 1;

      tx.set(linkRef, {
        organizationId,
        productId,
        recipeVersionId,
        ingredients,
        createdAt: existing.exists ? existing.data()!.createdAt : now,
        updatedAt: now,
        revision,
      });

      return { linkId: linkRef.id, revision };
    });
  },
);
