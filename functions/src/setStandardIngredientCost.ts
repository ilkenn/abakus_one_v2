import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission } from "./staffAuthorization";

/**
 * `setStandardIngredientCost` — AP-5 Sprint 5.
 *
 * The real, manager-tier writer for `standardIngredientCosts` — closing a
 * gap this sprint found by reading source rather than assuming: the
 * client-side `costing` feature (`lib/features/costing/domain/
 * standard_ingredient_cost.dart`, `StandardCostResolver`/
 * `WeightedAverageCostResolver`/`LatestPurchaseCostResolver`) is real and
 * tested, but 100% in-memory — no Firestore collection, no Cloud Function,
 * confirmed by an exhaustive `functions/src` grep. Without this, nothing
 * server-side (`acceptOrderLine.ts`'s cost-snapshot step) has a real unit
 * cost to read. Mirrors `setRecipeIngredientLink.ts`'s exact shape: one
 * document per `ingredientId` (deterministic id `cost-${ingredientId}`),
 * upserted, `revision` increments on every call.
 *
 * No `currency` field — this server's money representation is
 * `amountMinorUnits`-only everywhere else (`paymentDomain.ts` et al.), no
 * TS file in this codebase carries an explicit currency field; kept
 * consistent rather than introducing one here alone.
 */

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  return raw;
}

export const setStandardIngredientCost = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const ingredientId = requireString(data.ingredientId, "ingredientId");
    const unitCode = requireString(data.unitCode, "unitCode");
    if (
      typeof data.unitCostAmountMinorUnits !== "number" ||
      !Number.isInteger(data.unitCostAmountMinorUnits) ||
      data.unitCostAmountMinorUnits < 0
    ) {
      throw new HttpsError(
        "invalid-argument",
        "unitCostAmountMinorUnits must be a non-negative integer.",
      );
    }
    const unitCostAmountMinorUnits = data.unitCostAmountMinorUnits;

    requireStaffPermission(request, organizationId, "manageRecipes");

    const db = getFirestore();
    const costRef = db.collection("standardIngredientCosts").doc(`cost-${ingredientId}`);

    return db.runTransaction(async (tx) => {
      const existing = await tx.get(costRef);
      const now = Timestamp.now();
      const revision = existing.exists ? ((existing.data()!.revision as number) + 1) : 1;

      tx.set(costRef, {
        organizationId,
        ingredientId,
        unitCostAmountMinorUnits,
        unitCode,
        setByStaffId: request.auth!.uid,
        createdAt: existing.exists ? existing.data()!.createdAt : now,
        updatedAt: now,
        revision,
      });

      return { costId: costRef.id, revision };
    });
  },
);
