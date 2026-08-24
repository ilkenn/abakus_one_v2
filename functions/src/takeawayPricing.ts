import { vatAmountOf } from "./takeawayMoney";
import type { CanonicalChannelPricingPolicy, CanonicalMenuProduct } from "./takeawayCatalog";

/**
 * Server-authoritative pricing engine — Faz D.3. Hand-mirrors
 * `ChannelPriceResolver`/`OrderLine.create`/`PriceCalculator` (Dart)
 * exactly, operating on integer TRY minor units throughout
 * (`takeawayMoney.ts`) instead of `Money`. Same "no Dart<->TypeScript
 * sharing mechanism" duplication precedent as every other mirrored file
 * in this codebase — the Dart files remain the source of truth for the
 * *design* of this pricing model; this is its first-ever server-side
 * enforcement.
 */

export class NegativeAmountError extends Error {}

/** Mirrors `ChannelPricingPolicy.adjustmentFor`: a category override wins outright, else the channel's own default, else zero. */
export function categoryAdjustmentFor(
  policy: CanonicalChannelPricingPolicy,
  channel: string,
  categoryId: string,
): number {
  const categoryOverride = policy.categoryOverrides[channel]?.[categoryId];
  if (typeof categoryOverride === "number") return categoryOverride;
  return channelDefaultAdjustmentFor(policy, channel);
}

/** Mirrors `ChannelPricingPolicy.defaultAdjustmentFor`. */
export function channelDefaultAdjustmentFor(
  policy: CanonicalChannelPricingPolicy,
  channel: string,
): number {
  const value = policy.channelDefaultAdjustments[channel];
  return typeof value === "number" ? value : 0;
}

/**
 * Mirrors `ChannelPriceResolver.resolveProductUnitPrice`'s exact
 * precedence: the product's own `channelPriceOverrides[channel]` wins
 * outright (`explicitPrice` replaces the price entirely, `fixedAdjustment`
 * adds to `basePriceMinorUnits`); `useDefault` or no entry at all falls
 * through to the policy's category override, then channel default, then
 * zero.
 */
export function resolveProductUnitPriceMinorUnits(params: {
  product: CanonicalMenuProduct;
  channel: string;
  policy: CanonicalChannelPricingPolicy;
}): number {
  const { product, channel, policy } = params;
  const override = product.channelPriceOverrides[channel];

  let resolved: number;
  if (override?.type === "explicitPrice") {
    resolved = override.priceMinorUnits;
  } else if (override?.type === "fixedAdjustment") {
    resolved = product.basePriceMinorUnits + override.adjustmentMinorUnits;
  } else {
    resolved =
      product.basePriceMinorUnits + categoryAdjustmentFor(policy, channel, product.categoryId);
  }

  if (resolved < 0) {
    throw new NegativeAmountError(`resolved unit price for product "${product.id}" is negative`);
  }
  return resolved;
}

/**
 * Mirrors `ChannelPriceResolver.resolveBowlUnitPrice` with a zero
 * ingredient total fed in — isolates just the channel-wide default
 * adjustment (Bowl Builder has no `MenuCategory`/product-level override
 * of its own), applied exactly **once per bowl unit** by the caller
 * (never per ingredient — see `buildBowlOrderLine`).
 */
export function resolveBowlUnitAdjustmentMinorUnits(params: {
  channel: string;
  policy: CanonicalChannelPricingPolicy;
}): number {
  const resolved = channelDefaultAdjustmentFor(params.policy, params.channel);
  if (resolved < 0) {
    throw new NegativeAmountError("resolved bowl channel adjustment is negative");
  }
  return resolved;
}

export interface OrderLineModifierInput {
  groupId: string;
  groupName: string;
  optionId: string;
  optionName: string;
  unitExtraPriceMinorUnits: number;
  quantity: number;
}

export interface ComputedOrderLine {
  productId: string;
  productName: string;
  modifiers: OrderLineModifierInput[];
  quantity: number;
  unitPriceMinorUnits: number;
  modifierTotalMinorUnits: number;
  lineSubtotalMinorUnits: number;
  lineDiscountMinorUnits: number;
  lineTotalMinorUnits: number;
  taxBasisPoints: number;
  vatAmountMinorUnits: number;
  taxableBaseMinorUnits: number;
  kitchenNote: string;
  customerNote: string;
}

/**
 * Mirrors `OrderLine.create`'s exact computation — `modifierTotal`,
 * `lineSubtotal = (unitPrice + modifierTotal) * quantity`, `lineTotal`,
 * and gross-to-VAT extraction, deterministically from raw inputs, never
 * independently supplied. No line-level discount exists in this flow for
 * an ordinary line (takeaway had none at all until this phase, matching
 * `CartToOrderMapper`'s own takeaway call site never passing one) —
 * `freeUnitCount` defaults to `0`, giving `lineDiscountMinorUnits: 0`
 * exactly as before for every existing caller.
 *
 * **Boncuk Loyalty P7-C (2026-08-24) — `freeUnitCount`, the smallest
 * canonical pricing change able to represent "exactly one unit of this
 * line is free" without corrupting quantity math.** Because every unit
 * within one line is already priced identically (same `unitPriceMinorUnits`
 * + the same per-unit `modifierTotalMinorUnits`, per `OrderLine`'s own
 * design — a line is N identical units of one product+modifier
 * combination), a FLAT discount equal to exactly `freeUnitCount` units'
 * worth of (unitPrice + modifierTotal) is mathematically exact, not an
 * approximation: `lineTotal = (unitPrice + modifierTotal) *
 * (quantity - freeUnitCount)`, i.e. precisely "freeUnitCount units free,
 * the rest at full price" — never a percentage or a post-hoc grandTotal
 * adjustment. `unitPriceMinorUnits` is already the CHANNEL-RESOLVED price
 * (e.g. takeaway's own +20 TL product-level surcharge, folded in by
 * `resolveProductUnitPriceMinorUnits` before this function ever sees it)
 * — so covering it automatically covers that surcharge too, with no
 * separate surcharge-specific logic anywhere in this function. VAT is
 * extracted from `lineTotalMinorUnits` (i.e. AFTER the discount), exactly
 * as before — a free unit correctly owes no VAT, since VAT is only ever
 * due on money actually collected.
 */
export function buildOrderLine(params: {
  productId: string;
  productName: string;
  modifiers: OrderLineModifierInput[];
  quantity: number;
  unitPriceMinorUnits: number;
  taxBasisPoints: number;
  kitchenNote?: string;
  customerNote?: string;
  freeUnitCount?: number;
}): ComputedOrderLine {
  const { productId, productName, modifiers, quantity, unitPriceMinorUnits, taxBasisPoints } =
    params;
  const freeUnitCount = params.freeUnitCount ?? 0;

  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw new NegativeAmountError(
      `quantity for product "${productId}" must be a positive integer (mirrors OrderLine.create's NonPositiveQuantityViolation)`,
    );
  }
  if (!Number.isInteger(freeUnitCount) || freeUnitCount < 0 || freeUnitCount > quantity) {
    throw new NegativeAmountError(
      `freeUnitCount for product "${productId}" must be a non-negative integer no greater than quantity`,
    );
  }

  const modifierTotalMinorUnits = modifiers.reduce(
    (sum, m) => sum + m.unitExtraPriceMinorUnits * m.quantity,
    0,
  );
  const lineSubtotalMinorUnits = (unitPriceMinorUnits + modifierTotalMinorUnits) * quantity;
  const lineDiscountMinorUnits = (unitPriceMinorUnits + modifierTotalMinorUnits) * freeUnitCount;
  const lineTotalMinorUnits = lineSubtotalMinorUnits - lineDiscountMinorUnits;
  if (lineTotalMinorUnits < 0) {
    throw new NegativeAmountError(`computed lineTotal for product "${productId}" is negative`);
  }

  const vatAmountMinorUnits = vatAmountOf(lineTotalMinorUnits, taxBasisPoints);
  const taxableBaseMinorUnits = lineTotalMinorUnits - vatAmountMinorUnits;

  return {
    productId,
    productName,
    modifiers,
    quantity,
    unitPriceMinorUnits,
    modifierTotalMinorUnits,
    lineSubtotalMinorUnits,
    lineDiscountMinorUnits,
    lineTotalMinorUnits,
    taxBasisPoints,
    vatAmountMinorUnits,
    taxableBaseMinorUnits,
    kitchenNote: params.kitchenNote ?? "",
    customerNote: params.customerNote ?? "",
  };
}

export interface ComputedPriceBreakdown {
  grossSubtotalMinorUnits: number;
  taxableBaseMinorUnits: number;
  vatAmountMinorUnits: number;
  grandTotalMinorUnits: number;
}

/**
 * Mirrors `PriceCalculator.calculate` for the takeaway case specifically
 * — no discount/service/delivery/packaging/tip (matches
 * `CartToOrderMapper`'s own takeaway call site, which passes none of
 * these either): `grandTotal == grossSubtotal` exactly.
 */
export function computeOrderPriceBreakdown(lines: ComputedOrderLine[]): ComputedPriceBreakdown {
  let grossSubtotalMinorUnits = 0;
  let taxableBaseMinorUnits = 0;
  let vatAmountMinorUnits = 0;
  for (const line of lines) {
    grossSubtotalMinorUnits += line.lineTotalMinorUnits;
    taxableBaseMinorUnits += line.taxableBaseMinorUnits;
    vatAmountMinorUnits += line.vatAmountMinorUnits;
  }
  return {
    grossSubtotalMinorUnits,
    taxableBaseMinorUnits,
    vatAmountMinorUnits,
    grandTotalMinorUnits: grossSubtotalMinorUnits,
  };
}
