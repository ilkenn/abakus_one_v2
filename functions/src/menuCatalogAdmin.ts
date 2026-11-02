import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission } from "./staffAuthorization";

/**
 * 2026-10-28 — the admin Menü module's backend. `menuCategories`/
 * `menuProducts` carry NO `firestore.rules` entry at all (confirmed:
 * served only via callables, the same documented reasoning already
 * governing `reservationAreas`/`reservationPolicies` — see that comment
 * block in `firestore.rules`), so a direct client read/write was never
 * possible here; these four callables are the first real backend surface
 * for managing the catalog an admin actually sees, gated by the new
 * `manageMenu` permission (manager-tier-and-above, mirrors `manageRecipes`/
 * `manageInventory`'s own tier exactly — see that permission's own doc
 * comment in `staffAuthorization.ts`).
 *
 * Field shapes mirror `catalogMigration.ts`'s `migrateCanonicalCatalog`
 * byte-for-byte — the one other real writer of these two collections —
 * never invented independently.
 *
 * v1 scope was list + create only (no update/delete/reorder, deliberately
 * not built ahead of being asked for). 2026-10-30 — the product owner
 * explicitly asked for product edit/remove/availability-toggle ("Tükendi
 * /86") from the admin Menü screen, so `updateMenuProduct`/
 * `deleteMenuProduct`/`setMenuProductAvailability` close that gap now,
 * same `manageMenu` gate, same organization-ownership verification.
 */

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) invalid(`${field} is required.`);
  return value as string;
}
function requireAuth(request: CallableRequest): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  return request.auth.uid;
}

function db() {
  return getFirestore();
}

export const listMenuCategories = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requireAuth(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    await requireStaffPermission(request, organizationId, "manageMenu");

    const snap = await db()
      .collection("menuCategories")
      .where("organizationId", "==", organizationId)
      .get();

    return {
      categories: snap.docs.map((doc) => {
        const c = doc.data();
        return {
          id: doc.id,
          name: c.name,
          sortOrder: c.sortOrder,
          isActive: c.isActive,
          defaultStation: c.defaultStation ?? null,
        };
      }),
    };
  },
);

export const createMenuCategory = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requireAuth(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const restaurantId = requireNonEmptyString(data.restaurantId, "restaurantId");
    const name = requireNonEmptyString(data.name, "name");
    const sortOrder = typeof data.sortOrder === "number" ? data.sortOrder : 0;
    const defaultStation =
      typeof data.defaultStation === "string" && data.defaultStation.length > 0
        ? data.defaultStation
        : null;
    await requireStaffPermission(request, organizationId, "manageMenu");

    const ref = await db().collection("menuCategories").add({
      organizationId,
      restaurantId,
      name,
      sortOrder,
      isActive: true,
      defaultStation,
    });

    return { id: ref.id };
  },
);

export const listMenuProducts = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requireAuth(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    await requireStaffPermission(request, organizationId, "manageMenu");

    const snap = await db()
      .collection("menuProducts")
      .where("organizationId", "==", organizationId)
      .get();

    return {
      products: snap.docs.map((doc) => {
        const p = doc.data();
        return {
          id: doc.id,
          categoryId: p.categoryId,
          name: p.name,
          basePriceMinorUnits: p.basePriceMinorUnits,
          isAvailable: p.isAvailable,
        };
      }),
    };
  },
);

export const createMenuProduct = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requireAuth(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const restaurantId = requireNonEmptyString(data.restaurantId, "restaurantId");
    const categoryId = requireNonEmptyString(data.categoryId, "categoryId");
    const name = requireNonEmptyString(data.name, "name");
    const basePriceMinorUnits = data.basePriceMinorUnits;
    if (typeof basePriceMinorUnits !== "number" || basePriceMinorUnits < 0) {
      invalid("basePriceMinorUnits must be a non-negative number.");
    }
    await requireStaffPermission(request, organizationId, "manageMenu");

    const categorySnap = await db().collection("menuCategories").doc(categoryId).get();
    if (!categorySnap.exists || categorySnap.data()?.organizationId !== organizationId) {
      throw new HttpsError("not-found", `Category "${categoryId}" not found for this organization.`);
    }

    const ref = await db().collection("menuProducts").add({
      organizationId,
      restaurantId,
      categoryId,
      name,
      basePriceMinorUnits,
      isAvailable: true,
      modifierGroups: [],
      channelPriceOverrides: {},
    });

    return { id: ref.id };
  },
);

/** Shared ownership check every mutation below needs before touching a product. */
async function loadOwnedProductRef(organizationId: string, productId: string) {
  const ref = db().collection("menuProducts").doc(productId);
  const snap = await ref.get();
  if (!snap.exists || snap.data()?.organizationId !== organizationId) {
    throw new HttpsError("not-found", `Product "${productId}" not found for this organization.`);
  }
  return ref;
}

/** Renames a product and/or changes its price — category reassignment is out of this v2 scope (not asked for). */
export const updateMenuProduct = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requireAuth(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const productId = requireNonEmptyString(data.productId, "productId");
    await requireStaffPermission(request, organizationId, "manageMenu");

    const update: Record<string, unknown> = {};
    if (data.name !== undefined) {
      update.name = requireNonEmptyString(data.name, "name");
    }
    if (data.basePriceMinorUnits !== undefined) {
      if (typeof data.basePriceMinorUnits !== "number" || data.basePriceMinorUnits < 0) {
        invalid("basePriceMinorUnits must be a non-negative number.");
      }
      update.basePriceMinorUnits = data.basePriceMinorUnits;
    }
    if (Object.keys(update).length === 0) {
      invalid("at least one of name/basePriceMinorUnits must be provided.");
    }

    const ref = await loadOwnedProductRef(organizationId, productId);
    await ref.update(update);

    return { id: productId, updated: true };
  },
);

/** The "Tükendi (86)" toggle — sets isAvailable only, nothing else. */
export const setMenuProductAvailability = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requireAuth(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const productId = requireNonEmptyString(data.productId, "productId");
    if (typeof data.isAvailable !== "boolean") {
      invalid("isAvailable must be a boolean.");
    }
    await requireStaffPermission(request, organizationId, "manageMenu");

    const ref = await loadOwnedProductRef(organizationId, productId);
    await ref.update({ isAvailable: data.isAvailable });

    return { id: productId, isAvailable: data.isAvailable };
  },
);

/** Hard-deletes a product. No order-history/foreign-key check: an already-placed order's own OrderLine is a frozen snapshot (productId/productName/price all captured at submission time, per that model's own doc comment) and never re-reads the live menuProducts document, so deleting a product here cannot retroactively corrupt a past order. */
export const deleteMenuProduct = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requireAuth(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
    const productId = requireNonEmptyString(data.productId, "productId");
    await requireStaffPermission(request, organizationId, "manageMenu");

    const ref = await loadOwnedProductRef(organizationId, productId);
    await ref.delete();

    return { id: productId, deleted: true };
  },
);
