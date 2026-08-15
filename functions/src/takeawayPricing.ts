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
 * independently supplied. No line-level discount exists in this flow
 * (takeaway has none today, matching `CartToOrderMapper`'s own takeaway
 * call site never passing one) — `lineDiscountMinorUnits` is always 0,
 * kept as an explicit field for shape-fidelity with `OrderLine` rather
 * than silently omitted.
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
}): ComputedOrderLine {
  const { productId, productName, modifiers, quantity, unitPriceMinorUnits, taxBasisPoints } =
    params;

  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw new NegativeAmountError(
      `quantity for product "${productId}" must be a positive integer (mirrors OrderLine.create's NonPositiveQuantityViolation)`,
    );
  }

  const modifierTotalMinorUnits = modifiers.reduce(
    (sum, m) => sum + m.unitExtraPriceMinorUnits * m.quantity,
    0,
  );
  const lineSubtotalMinorUnits = (unitPriceMinorUnits + modifierTotalMinorUnits) * quantity;
  const lineDiscountMinorUnits = 0;
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
