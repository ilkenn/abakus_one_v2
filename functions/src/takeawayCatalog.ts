import type { Firestore, Transaction } from "firebase-admin/firestore";

/**
 * Canonical, Firestore-backed catalog types + loaders — Faz D.3. Closes
 * the Faz D architecture analysis's REQUIRED finding: a backend that can
 * independently verify product identity/availability/category/price
 * without trusting the client. Firestore-canonical representation of the
 * existing Dart domain model (`MenuProduct`/`ModifierGroup`/
 * `ModifierOption`/`ChannelPricingPolicy`/`ChannelPriceRule`/
 * `BowlBuilderIngredient`) — no new, parallel pricing model invented.
 * Prices are stored as integer minor units (kuruş), never a float,
 * matching `Money`'s own domain-layer discipline (`takeawayMoney.ts`).
 *
 * **Scope decision, stated explicitly**: this phase seeds a
 * *representative* canonical subset (a handful of products spanning every
 * pricing rule — a drink, a normal product, an explicit-override product,
 * a fixed-adjustment product, a product with modifier groups, a few bowl
 * ingredients) — not the full ~84-product real menu
 * (`AbakusMenuCatalog`). A full content migration is separate, future
 * work (RECOMMENDED finding, this phase's own report) — this phase's job
 * is proving the *pricing engine* is correct and authoritative, not
 * replatforming menu content.
 */

export type CanonicalChannelPriceRule =
  | { type: "useDefault" }
  | { type: "fixedAdjustment"; adjustmentMinorUnits: number }
  | { type: "explicitPrice"; priceMinorUnits: number };

export interface CanonicalModifierOption {
  id: string;
  name: string;
  extraPriceMinorUnits: number;
  isAvailable: boolean;
}

export interface CanonicalModifierGroup {
  id: string;
  name: string;
  selectionType: "single" | "multiple";
  isRequired: boolean;
  minSelections: number;
  maxSelections: number;
  options: CanonicalModifierOption[];
}

export interface CanonicalMenuProduct {
  id: string;
  organizationId: string;
  restaurantId: string;
  categoryId: string;
  name: string;
  isAvailable: boolean;
  basePriceMinorUnits: number;
  modifierGroups: CanonicalModifierGroup[];
  channelPriceOverrides: Record<string, CanonicalChannelPriceRule>;
}

export interface CanonicalBowlIngredient {
  id: string;
  organizationId: string;
  restaurantId: string;
  categoryId: string;
  name: string;
  priceMinorUnits: number;
  isAvailable: boolean;
}

export interface CanonicalChannelPricingPolicy {
  channelDefaultAdjustments: Record<string, number>;
  categoryOverrides: Record<string, Record<string, number>>;
}

function parseChannelPriceOverrides(
  raw: unknown,
): Record<string, CanonicalChannelPriceRule> {
  if (typeof raw !== "object" || raw === null) return {};
  const result: Record<string, CanonicalChannelPriceRule> = {};
  for (const [channel, value] of Object.entries(raw as Record<string, unknown>)) {
    if (typeof value !== "object" || value === null) continue;
    const rule = value as Record<string, unknown>;
    if (rule.type === "explicitPrice" && typeof rule.priceMinorUnits === "number") {
      result[channel] = { type: "explicitPrice", priceMinorUnits: rule.priceMinorUnits };
    } else if (rule.type === "fixedAdjustment" && typeof rule.adjustmentMinorUnits === "number") {
      result[channel] = { type: "fixedAdjustment", adjustmentMinorUnits: rule.adjustmentMinorUnits };
    } else {
      result[channel] = { type: "useDefault" };
    }
  }
  return result;
}

function parseModifierGroups(raw: unknown): CanonicalModifierGroup[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((group: Record<string, unknown>) => ({
    id: String(group.id ?? ""),
    name: String(group.name ?? ""),
    selectionType: group.selectionType === "multiple" ? "multiple" : "single",
    isRequired: group.isRequired === true,
    minSelections: typeof group.minSelections === "number" ? group.minSelections : 0,
    maxSelections: typeof group.maxSelections === "number" ? group.maxSelections : 1,
    options: Array.isArray(group.options)
      ? (group.options as Record<string, unknown>[]).map((option) => ({
          id: String(option.id ?? ""),
          name: String(option.name ?? ""),
          extraPriceMinorUnits:
            typeof option.extraPriceMinorUnits === "number" ? option.extraPriceMinorUnits : 0,
          isAvailable: option.isAvailable !== false,
        }))
      : [],
  }));
}

/**
 * `null` if the product doesn't exist. Never throws for "not found" — the
 * caller decides what that means (reject the order).
 *
 * **Faz R.1D.1 — optional `tx` parameter.** Every existing call site
 * (`submitTakeawayOrder.ts`) keeps calling this with a plain `db`,
 * unaffected, and keeps its existing (pre-Faz-R.1A.1-discipline) behavior
 * exactly as before — not touched by this phase, out of scope. When a
 * caller *does* pass a `tx` (the new `reservationPreorder.ts`, whose reads
 * must participate in `submitReservation`'s own transaction), the read
 * goes through `tx.get()` instead, so it's part of that transaction's
 * optimistic-concurrency read-set — consistent with the "every
 * authoritative transactional read is `tx.get()`" rule this reservation
 * arc has enforced everywhere else (`reservationConfig.ts`'s own
 * `loadReservationPolicy` doc comment explains the reasoning in full).
 */
export async function loadCanonicalMenuProduct(
  db: Firestore,
  productId: string,
  tx?: Transaction,
): Promise<CanonicalMenuProduct | null> {
  const ref = db.collection("menuProducts").doc(productId);
  const doc = tx ? await tx.get(ref) : await ref.get();
  if (!doc.exists) return null;
  const data = doc.data()!;
  return {
    id: doc.id,
    organizationId: String(data.organizationId ?? ""),
    restaurantId: String(data.restaurantId ?? ""),
    categoryId: String(data.categoryId ?? ""),
    name: String(data.name ?? ""),
    isAvailable: data.isAvailable !== false,
    basePriceMinorUnits:
      typeof data.basePriceMinorUnits === "number" ? data.basePriceMinorUnits : 0,
    modifierGroups: parseModifierGroups(data.modifierGroups),
    channelPriceOverrides: parseChannelPriceOverrides(data.channelPriceOverrides),
  };
}

/** Faz R.1D.1 — optional `tx` parameter, same reasoning/backward-compatibility as `loadCanonicalMenuProduct` above. */
export async function loadCanonicalBowlIngredient(
  db: Firestore,
  ingredientId: string,
  tx?: Transaction,
): Promise<CanonicalBowlIngredient | null> {
  const ref = db.collection("bowlIngredients").doc(ingredientId);
  const doc = tx ? await tx.get(ref) : await ref.get();
  if (!doc.exists) return null;
  const data = doc.data()!;
  return {
    id: doc.id,
    organizationId: String(data.organizationId ?? ""),
    restaurantId: String(data.restaurantId ?? ""),
    categoryId: String(data.categoryId ?? ""),
    name: String(data.name ?? ""),
    priceMinorUnits: typeof data.priceMinorUnits === "number" ? data.priceMinorUnits : 0,
    isAvailable: data.isAvailable !== false,
  };
}

/**
 * An empty policy (every channel/category resolves to a zero adjustment)
 * if no document exists yet for this restaurant — mirrors
 * `InMemoryChannelPricingPolicyRepository`'s own "no policy set = zero
 * adjustment" fallback, never a thrown error for a restaurant that hasn't
 * configured one.
 *
 * Faz R.1D.1 — optional `tx` parameter, same reasoning/backward-
 * compatibility as `loadCanonicalMenuProduct` above.
 */
export async function loadCanonicalChannelPricingPolicy(
  db: Firestore,
  restaurantId: string,
  tx?: Transaction,
): Promise<CanonicalChannelPricingPolicy> {
  const ref = db.collection("channelPricingPolicies").doc(restaurantId);
  const doc = tx ? await tx.get(ref) : await ref.get();
  if (!doc.exists) {
    return { channelDefaultAdjustments: {}, categoryOverrides: {} };
  }
  const data = doc.data()!;
  return {
    channelDefaultAdjustments:
      typeof data.channelDefaultAdjustments === "object" && data.channelDefaultAdjustments !== null
        ? (data.channelDefaultAdjustments as Record<string, number>)
        : {},
    categoryOverrides:
      typeof data.categoryOverrides === "object" && data.categoryOverrides !== null
        ? (data.categoryOverrides as Record<string, Record<string, number>>)
        : {},
  };
}
