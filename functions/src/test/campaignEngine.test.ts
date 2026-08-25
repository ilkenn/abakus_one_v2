import { test } from "node:test";
import assert from "node:assert";
import { Timestamp } from "firebase-admin/firestore";
import {
  sanitizeCampaignId,
  sanitizeCampaignTitle,
  sanitizeCampaignType,
  sanitizeCampaignRule,
  sanitizeCampaignEligibleChannels,
  sanitizeOptionalEligibleProductIds,
  sanitizeOptionalEligibleCategoryIds,
  sanitizeOptionalMinimumBasketMinorUnits,
  sanitizeOptionalUsageLimit,
  validateCampaignTypeRuleConsistency,
  ruleReferencedProductIds,
  ruleReferencedCategoryIds,
  isCampaignCurrentlyEligible,
  parseCampaignDefinition,
  sanitizeCustomerCampaign,
  campaignVersionDocId,
  type CampaignDefinition,
} from "../campaignEngine";
import { DEFAULT_ORGANIZATION_TIMEZONE } from "../campaignScheduling";

/**
 * Pure, no-emulator unit tests for `campaignEngine.ts`'s domain
 * types/sanitizers — Server-Authoritative Campaign Engine P8-B
 * (2026-08-25).
 */

// ===========================================================================
// sanitizeCampaignId
// ===========================================================================

test("sanitizeCampaignId: accepts a lowercase alphanumeric-hyphen slug", () => {
  assert.strictEqual(sanitizeCampaignId("hafta-ici-ogle"), "hafta-ici-ogle");
});

test("sanitizeCampaignId: rejects uppercase, spaces, and leading/trailing hyphens", () => {
  assert.throws(() => sanitizeCampaignId("Hafta-Ici"), RangeError);
  assert.throws(() => sanitizeCampaignId("hafta ici"), RangeError);
  assert.throws(() => sanitizeCampaignId("-hafta"), RangeError);
  assert.throws(() => sanitizeCampaignId("hafta-"), RangeError);
});

// ===========================================================================
// sanitizeCampaignTitle
// ===========================================================================

test("sanitizeCampaignTitle: trims and rejects empty", () => {
  assert.strictEqual(sanitizeCampaignTitle("  %15 İndirim  "), "%15 İndirim");
  assert.throws(() => sanitizeCampaignTitle("   "), RangeError);
});

// ===========================================================================
// sanitizeCampaignType / campaignType-rule consistency
// ===========================================================================

test("sanitizeCampaignType: accepts exactly the six locked Admin-facing types", () => {
  for (const t of [
    "percentageDiscount",
    "fixedAmountDiscount",
    "freeProduct",
    "buyXGetY",
    "productDiscount",
    "categoryDiscount",
  ]) {
    assert.strictEqual(sanitizeCampaignType(t), t);
  }
  assert.throws(() => sanitizeCampaignType("somethingElse"), RangeError);
});

test("validateCampaignTypeRuleConsistency: percentageDiscount requires order-scoped percentage rule", () => {
  assert.doesNotThrow(() =>
    validateCampaignTypeRuleConsistency("percentageDiscount", {
      mechanic: "percentage",
      percentBasisPoints: 1000,
      scope: { kind: "order" },
    }),
  );
  assert.throws(() =>
    validateCampaignTypeRuleConsistency("percentageDiscount", {
      mechanic: "percentage",
      percentBasisPoints: 1000,
      scope: { kind: "product", productId: "x" },
    }),
  );
  assert.throws(() =>
    validateCampaignTypeRuleConsistency("percentageDiscount", {
      mechanic: "fixedAmount",
      amountMinorUnits: 1000,
      scope: { kind: "order" },
    }),
  );
});

test("validateCampaignTypeRuleConsistency: productDiscount requires product-scoped percentage or fixedAmount rule", () => {
  assert.doesNotThrow(() =>
    validateCampaignTypeRuleConsistency("productDiscount", {
      mechanic: "percentage",
      percentBasisPoints: 2000,
      scope: { kind: "product", productId: "falafel-salad" },
    }),
  );
  assert.throws(() =>
    validateCampaignTypeRuleConsistency("productDiscount", {
      mechanic: "percentage",
      percentBasisPoints: 2000,
      scope: { kind: "order" },
    }),
  );
  assert.throws(() =>
    validateCampaignTypeRuleConsistency("productDiscount", {
      mechanic: "percentage",
      percentBasisPoints: 2000,
      scope: { kind: "category", categoryId: "pasta" },
    }),
  );
});

test("validateCampaignTypeRuleConsistency: categoryDiscount requires category-scoped rule", () => {
  assert.doesNotThrow(() =>
    validateCampaignTypeRuleConsistency("categoryDiscount", {
      mechanic: "fixedAmount",
      amountMinorUnits: 1000,
      scope: { kind: "category", categoryId: "pasta" },
    }),
  );
  assert.throws(() =>
    validateCampaignTypeRuleConsistency("categoryDiscount", {
      mechanic: "fixedAmount",
      amountMinorUnits: 1000,
      scope: { kind: "product", productId: "x" },
    }),
  );
});

test("validateCampaignTypeRuleConsistency: freeProduct/buyXGetY require their own matching mechanic", () => {
  assert.doesNotThrow(() => validateCampaignTypeRuleConsistency("freeProduct", { mechanic: "freeProduct", freeProductId: "icecek" }));
  assert.throws(() =>
    validateCampaignTypeRuleConsistency("freeProduct", {
      mechanic: "percentage",
      percentBasisPoints: 100,
      scope: { kind: "order" },
    }),
  );
  assert.doesNotThrow(() =>
    validateCampaignTypeRuleConsistency("buyXGetY", {
      mechanic: "buyXGetY",
      triggerProductId: "a",
      triggerQuantity: 2,
      rewardProductId: "b",
      rewardQuantity: 1,
    }),
  );
  assert.throws(() => validateCampaignTypeRuleConsistency("buyXGetY", { mechanic: "freeProduct", freeProductId: "a" }));
});

// ===========================================================================
// sanitizeCampaignRule — shape validation
// ===========================================================================

test("sanitizeCampaignRule: percentage rejects a percentage above 100%", () => {
  assert.throws(
    () => sanitizeCampaignRule({ mechanic: "percentage", percentBasisPoints: 10001, scope: { kind: "order" } }),
    RangeError,
  );
});

test("sanitizeCampaignRule: rejects an unknown mechanic", () => {
  assert.throws(() => sanitizeCampaignRule({ mechanic: "magic" }), RangeError);
});

test("sanitizeCampaignRule: buyXGetY validates all four fields", () => {
  const rule = sanitizeCampaignRule({
    mechanic: "buyXGetY",
    triggerProductId: "bowl",
    triggerQuantity: 2,
    rewardProductId: "icecek",
    rewardQuantity: 1,
  });
  assert.deepStrictEqual(rule, {
    mechanic: "buyXGetY",
    triggerProductId: "bowl",
    triggerQuantity: 2,
    rewardProductId: "icecek",
    rewardQuantity: 1,
  });
});

// ===========================================================================
// eligibleChannels — reuses CANONICAL_COMMERCIAL_CHANNELS verbatim
// ===========================================================================

test("sanitizeCampaignEligibleChannels: normalizes to canonical order, rejects an invented channel", () => {
  assert.deepStrictEqual(sanitizeCampaignEligibleChannels(["takeaway", "dineIn"]), ["dineIn", "takeaway"]);
  assert.throws(() => sanitizeCampaignEligibleChannels(["dineIn", "posOnly"]), RangeError);
  assert.throws(() => sanitizeCampaignEligibleChannels([]), RangeError);
});

// ===========================================================================
// Optional targeting/basket/usage-limit sanitizers
// ===========================================================================

test("sanitizeOptionalEligibleProductIds: null/undefined both collapse to null", () => {
  assert.strictEqual(sanitizeOptionalEligibleProductIds(null), null);
  assert.strictEqual(sanitizeOptionalEligibleProductIds(undefined), null);
  assert.deepStrictEqual(sanitizeOptionalEligibleProductIds(["a", "a", "b"]), ["a", "b"]);
});

test("sanitizeOptionalEligibleCategoryIds: rejects an empty array (use null instead)", () => {
  assert.throws(() => sanitizeOptionalEligibleCategoryIds([]), RangeError);
});

test("sanitizeOptionalMinimumBasketMinorUnits: null is 'no minimum', negative is rejected", () => {
  assert.strictEqual(sanitizeOptionalMinimumBasketMinorUnits(null), null);
  assert.strictEqual(sanitizeOptionalMinimumBasketMinorUnits(5000), 5000);
  assert.throws(() => sanitizeOptionalMinimumBasketMinorUnits(-1), RangeError);
});

test("sanitizeOptionalUsageLimit: null is 'unlimited', zero and negative are rejected", () => {
  assert.strictEqual(sanitizeOptionalUsageLimit(null, "usageLimit"), null);
  assert.strictEqual(sanitizeOptionalUsageLimit(100, "usageLimit"), 100);
  assert.throws(() => sanitizeOptionalUsageLimit(0, "usageLimit"), RangeError);
  assert.throws(() => sanitizeOptionalUsageLimit(-5, "usageLimit"), RangeError);
});

// ===========================================================================
// ruleReferencedProductIds / ruleReferencedCategoryIds
// ===========================================================================

test("ruleReferencedProductIds: extracts every product id a rule can name", () => {
  assert.deepStrictEqual(
    ruleReferencedProductIds({ mechanic: "percentage", percentBasisPoints: 100, scope: { kind: "order" } }),
    [],
  );
  assert.deepStrictEqual(
    ruleReferencedProductIds({
      mechanic: "percentage",
      percentBasisPoints: 100,
      scope: { kind: "product", productId: "x" },
    }),
    ["x"],
  );
  assert.deepStrictEqual(ruleReferencedProductIds({ mechanic: "freeProduct", freeProductId: "y" }), ["y"]);
  assert.deepStrictEqual(
    ruleReferencedProductIds({
      mechanic: "buyXGetY",
      triggerProductId: "a",
      triggerQuantity: 1,
      rewardProductId: "b",
      rewardQuantity: 1,
    }),
    ["a", "b"],
  );
});

test("ruleReferencedCategoryIds: only category-scoped percentage/fixedAmount rules reference a category", () => {
  assert.deepStrictEqual(
    ruleReferencedCategoryIds({
      mechanic: "fixedAmount",
      amountMinorUnits: 100,
      scope: { kind: "category", categoryId: "pasta" },
    }),
    ["pasta"],
  );
  assert.deepStrictEqual(ruleReferencedCategoryIds({ mechanic: "freeProduct", freeProductId: "y" }), []);
});

// ===========================================================================
// isCampaignCurrentlyEligible / parseCampaignDefinition / sanitizeCustomerCampaign
// ===========================================================================

function fixtureCampaign(overrides: Partial<CampaignDefinition> = {}): CampaignDefinition {
  const now = Timestamp.now();
  return {
    campaignId: "test-campaign",
    organizationId: "org-1",
    title: "Test Campaign",
    description: "A test campaign.",
    campaignType: "percentageDiscount",
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
    eligibleChannels: ["dineIn", "takeaway"],
    eligibleProductIds: null,
    eligibleCategoryIds: null,
    minimumBasketMinorUnits: null,
    schedule: { mode: "oneTime", startAt: null, endAt: null },
    usageLimit: null,
    perCustomerUsageLimit: null,
    active: true,
    archived: false,
    sortOrder: 0,
    version: 1,
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

test("isCampaignCurrentlyEligible: inactive is never eligible regardless of schedule", () => {
  const campaign = fixtureCampaign({ active: false });
  assert.strictEqual(isCampaignCurrentlyEligible(campaign, Timestamp.now(), DEFAULT_ORGANIZATION_TIMEZONE), false);
});

test("isCampaignCurrentlyEligible: archived is never eligible even if active", () => {
  const campaign = fixtureCampaign({ active: true, archived: true });
  assert.strictEqual(isCampaignCurrentlyEligible(campaign, Timestamp.now(), DEFAULT_ORGANIZATION_TIMEZONE), false);
});

test("isCampaignCurrentlyEligible: active, non-archived, perpetually-open oneTime schedule is eligible", () => {
  const campaign = fixtureCampaign();
  assert.strictEqual(isCampaignCurrentlyEligible(campaign, Timestamp.now(), DEFAULT_ORGANIZATION_TIMEZONE), true);
});

test("parseCampaignDefinition: round-trips a well-formed document", () => {
  const campaign = fixtureCampaign();
  const parsed = parseCampaignDefinition({ ...campaign });
  assert.deepStrictEqual(parsed, campaign);
});

test("parseCampaignDefinition: returns null (never throws) for a malformed document", () => {
  assert.strictEqual(parseCampaignDefinition({ campaignId: "x" }), null);
  assert.strictEqual(parseCampaignDefinition(undefined), null);
});

test("parseCampaignDefinition: returns null for a campaignType/rule mismatch (tampered document)", () => {
  const campaign = fixtureCampaign({
    campaignType: "categoryDiscount",
    rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
  });
  assert.strictEqual(parseCampaignDefinition({ ...campaign }), null);
});

test("sanitizeCustomerCampaign: excludes organizationId/active/archived/usageLimit/perCustomerUsageLimit/createdAt/updatedAt", () => {
  const campaign = fixtureCampaign({ usageLimit: 100, perCustomerUsageLimit: 2 });
  const sanitized = sanitizeCustomerCampaign(campaign);
  assert.strictEqual("organizationId" in sanitized, false);
  assert.strictEqual("active" in sanitized, false);
  assert.strictEqual("archived" in sanitized, false);
  assert.strictEqual("usageLimit" in sanitized, false);
  assert.strictEqual("perCustomerUsageLimit" in sanitized, false);
  assert.strictEqual("createdAt" in sanitized, false);
  assert.strictEqual("updatedAt" in sanitized, false);
  assert.strictEqual(sanitized.campaignId, "test-campaign");
});

test("campaignVersionDocId: deterministic composite id", () => {
  assert.strictEqual(campaignVersionDocId("hafta-ici", 3), "hafta-ici_3");
});
