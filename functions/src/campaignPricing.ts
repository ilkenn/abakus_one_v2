import type { CampaignDefinition, CampaignRule } from "./campaignEngine";

/**
 * `campaignPricing` — Server-Authoritative Campaign Engine P8-B
 * (2026-08-25).
 *
 * Pure, side-effect-free discount-calculation engine — no Firestore I/O, no
 * transaction, no knowledge of any specific order-submission callable.
 * Mirrors `takeawayPricing.ts`'s own "pure calculator, channel-agnostic"
 * shape exactly, so a future checkout-integration phase (P8-C+) can call
 * this from any of the four `submit*Order.ts` files without a second,
 * channel-specific copy.
 *
 * **Insertion point discipline (locked P8-A/P8-B decision): line-level
 * discount, never a `grandTotal` patch.** [resolveCampaignDiscount] returns
 * a discount PER LINE — the sum of which a future integration would fold
 * into each line's own `lineTotal` at build time (generalizing
 * `buildOrderLine`'s existing `freeUnitCount` mechanism), exactly the same
 * insertion point `catalogReward` already uses. `pricing.discount` (today
 * hard-coded to zero in every channel) would become the sum of these
 * per-line discounts — never an order-level number invented independently
 * of what the lines themselves say.
 *
 * **Exact integer minor-unit allocation — the largest-remainder method.**
 * Distributing an order-wide percentage/fixed discount across N lines by
 * naive proportional multiplication produces fractional minor units
 * (kuruş), which cannot be stored. [allocateProportionally] floors every
 * line's raw share, then distributes the residual (`totalToAllocate -
 * Σfloors`, always a small non-negative integer strictly less than the
 * number of lines) one minor unit at a time to the lines with the largest
 * fractional remainder — the standard "largest remainder" apportionment
 * method, deterministic and exact: `Σ(result) === totalToAllocate` always,
 * proven by dedicated unit tests covering exact and inexact divisions.
 *
 * **Modifiers ARE included in the discountable base** (locked decision) —
 * every `CampaignPriceableLine.unitBaseMinorUnits` is expected to already
 * be `unitPrice + modifierTotal` (channel-resolved, matching
 * `buildOrderLine`'s own `(unitPriceMinorUnits + modifierTotalMinorUnits)`
 * base), so a percentage/fixed discount computed against it automatically
 * covers both channel surcharges AND modifiers — no separate surcharge- or
 * modifier-aware logic needed, identical to how `freeUnitCount` already
 * behaves.
 *
 * **Order-wide campaigns may affect Bowl Builder lines** (locked decision)
 * — `"order"`-scoped rules never filter by `productId`/`categoryId`, so a
 * bowl line (whose `productId` is `null`, since Bowl Builder items have no
 * real canonical product id) participates in the discount base exactly
 * like any other line. Product/category-scoped rules (`productDiscount`/
 * `categoryDiscount`/`freeProduct`/`buyXGetY`) can never match a bowl line,
 * for the same structural reason `catalogReward` cannot — this is proven
 * by `matchesScope`/`matchesProductId` returning `false` whenever a line's
 * own `productId` is `null`, never a special-cased bowl check.
 */

export interface CampaignPriceableLine {
  lineIndex: number;
  /** `null` for a Bowl Builder line — never a real canonical `menuProducts` id, matching `catalogReward`'s own established limitation. */
  productId: string | null;
  /** `null` whenever `productId` is `null`, or the product's category is otherwise unknown to the caller. */
  categoryId: string | null;
  quantity: number;
  /** Channel-resolved unit price INCLUDING modifiers (`unitPrice + modifierTotal`) — the same discountable base `freeUnitCount` already uses. */
  unitBaseMinorUnits: number;
}

export interface CampaignLineDiscount {
  lineIndex: number;
  discountMinorUnits: number;
}

export type ResolveCampaignDiscountResult =
  | {
      status: "applied";
      totalDiscountMinorUnits: number;
      lineDiscounts: CampaignLineDiscount[];
      appliedValue: number;
    }
  | { status: "minimum-basket-not-met" }
  | { status: "no-eligible-line" }
  | { status: "trigger-quantity-not-met" };

function lineSubtotal(line: CampaignPriceableLine): number {
  return line.unitBaseMinorUnits * line.quantity;
}

function matchesRuleScope(line: CampaignPriceableLine, scope: Extract<CampaignRule, { mechanic: "percentage" | "fixedAmount" }>["scope"]): boolean {
  if (scope.kind === "order") return true;
  if (scope.kind === "product") return line.productId !== null && line.productId === scope.productId;
  return line.categoryId !== null && line.categoryId === scope.categoryId;
}

/**
 * Largest-remainder apportionment — see this file's own doc comment.
 * `weights` with a non-positive total, or `totalToAllocate <= 0`, allocate
 * zero to every line (never a divide-by-zero, never a negative discount).
 */
export function allocateProportionally(
  totalToAllocate: number,
  weights: Array<{ lineIndex: number; weight: number }>,
): CampaignLineDiscount[] {
  const totalWeight = weights.reduce((sum, w) => sum + w.weight, 0);
  if (totalWeight <= 0 || totalToAllocate <= 0) {
    return weights.map((w) => ({ lineIndex: w.lineIndex, discountMinorUnits: 0 }));
  }
  const shares = weights.map((w) => {
    const exact = (totalToAllocate * w.weight) / totalWeight;
    const floor = Math.floor(exact);
    return { lineIndex: w.lineIndex, floor, remainder: exact - floor };
  });
  const allocatedFloor = shares.reduce((sum, s) => sum + s.floor, 0);
  let residual = totalToAllocate - allocatedFloor;
  const result = new Map<number, number>(shares.map((s) => [s.lineIndex, s.floor]));
  // Largest remainder first; ties broken by ascending lineIndex for
  // deterministic, reproducible output.
  const byRemainderDesc = [...shares].sort((a, b) => b.remainder - a.remainder || a.lineIndex - b.lineIndex);
  for (let i = 0; residual > 0 && i < byRemainderDesc.length; i++, residual--) {
    const entry = byRemainderDesc[i];
    result.set(entry.lineIndex, (result.get(entry.lineIndex) ?? 0) + 1);
  }
  return weights.map((w) => ({ lineIndex: w.lineIndex, discountMinorUnits: result.get(w.lineIndex) ?? 0 }));
}

/**
 * The one shared resolver every `campaignType`'s mechanic maps onto. Pure —
 * takes an already-loaded, already-channel-priced set of lines and an
 * already-validated campaign definition (channel/schedule/active eligibility
 * must be checked by the caller BEFORE calling this; this function only
 * computes the discount amount, it does not re-validate eligibility).
 *
 * Minimum-basket is evaluated against the PRE-CAMPAIGN basket amount
 * (locked decision) — the sum of every line's own subtotal, computed
 * before this function ever touches a discount.
 */
export function resolveCampaignDiscount(
  campaign: Pick<CampaignDefinition, "rule" | "minimumBasketMinorUnits">,
  lines: CampaignPriceableLine[],
): ResolveCampaignDiscountResult {
  const preCampaignBasketMinorUnits = lines.reduce((sum, line) => sum + lineSubtotal(line), 0);
  if (
    campaign.minimumBasketMinorUnits !== null &&
    preCampaignBasketMinorUnits < campaign.minimumBasketMinorUnits
  ) {
    return { status: "minimum-basket-not-met" };
  }

  const rule = campaign.rule;

  if (rule.mechanic === "percentage" || rule.mechanic === "fixedAmount") {
    const matching = lines.filter((line) => matchesRuleScope(line, rule.scope));
    if (matching.length === 0) return { status: "no-eligible-line" };
    const matchingBaseMinorUnits = matching.reduce((sum, line) => sum + lineSubtotal(line), 0);
    const rawDiscount =
      rule.mechanic === "percentage"
        ? Math.floor((matchingBaseMinorUnits * rule.percentBasisPoints) / 10_000)
        : Math.min(rule.amountMinorUnits, matchingBaseMinorUnits);
    if (rawDiscount <= 0) return { status: "no-eligible-line" };
    const lineDiscounts = allocateProportionally(
      rawDiscount,
      matching.map((line) => ({ lineIndex: line.lineIndex, weight: lineSubtotal(line) })),
    );
    return {
      status: "applied",
      totalDiscountMinorUnits: rawDiscount,
      lineDiscounts,
      appliedValue: rule.mechanic === "percentage" ? rule.percentBasisPoints : rule.amountMinorUnits,
    };
  }

  if (rule.mechanic === "freeProduct") {
    const target = lines.find((line) => line.productId !== null && line.productId === rule.freeProductId);
    if (!target) return { status: "no-eligible-line" };
    const discount = Math.min(target.unitBaseMinorUnits, lineSubtotal(target));
    if (discount <= 0) return { status: "no-eligible-line" };
    return {
      status: "applied",
      totalDiscountMinorUnits: discount,
      lineDiscounts: [{ lineIndex: target.lineIndex, discountMinorUnits: discount }],
      appliedValue: 1,
    };
  }

  // buyXGetY
  const triggerQuantityInCart = lines
    .filter((line) => line.productId !== null && line.productId === rule.triggerProductId)
    .reduce((sum, line) => sum + line.quantity, 0);
  if (triggerQuantityInCart < rule.triggerQuantity) {
    return { status: "trigger-quantity-not-met" };
  }
  const rewardTarget = lines.find((line) => line.productId !== null && line.productId === rule.rewardProductId);
  if (!rewardTarget) return { status: "no-eligible-line" };
  const freeUnits = Math.min(rule.rewardQuantity, rewardTarget.quantity);
  const discount = freeUnits * rewardTarget.unitBaseMinorUnits;
  if (discount <= 0) return { status: "no-eligible-line" };
  return {
    status: "applied",
    totalDiscountMinorUnits: discount,
    lineDiscounts: [{ lineIndex: rewardTarget.lineIndex, discountMinorUnits: discount }],
    appliedValue: freeUnits,
  };
}
