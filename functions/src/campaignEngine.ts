import { Timestamp } from "firebase-admin/firestore";
import {
  CANONICAL_COMMERCIAL_CHANNELS,
  sanitizeSortOrder,
  sanitizeOptionalTimestamp,
  validateValidityWindow,
  type CanonicalCommercialChannel,
} from "./loyaltyRewardCatalog";
import {
  sanitizeCampaignSchedule,
  sanitizeCampaignScheduleForWire,
  isCampaignScheduleCurrentlyOpen,
  type CampaignSchedule,
  type SanitizedCampaignSchedule,
} from "./campaignScheduling";

/**
 * `campaignEngine` — Server-Authoritative Campaign Engine P8-B (2026-08-25).
 *
 * Pure domain module: types, sanitizers, parsing — no Firestore I/O (see
 * `campaignAdminService.ts` for trusted writes, `getCustomerActiveCampaigns
 * .ts` for the customer read path, `campaignPricing.ts` for the pure
 * discount-calculation engine, `campaignUsage.ts` for the transactional
 * usage-reservation primitives). Mirrors `loyaltyRewardCatalog.ts`'s own
 * "pure domain module, no I/O" shape exactly — same author, same phase
 * family, same conventions, deliberately not reinvented.
 *
 * **Foundation only (P8-B).** This phase builds the data model, versioning,
 * scheduling, pricing-resolver, usage-reservation, and admin/customer read
 * primitives — it does NOT wire any of this into checkout/order submission.
 * `campaignType` is never selected by a client at checkout time this phase;
 * no `submitTakeawayOrder.ts`/`submitDeliveryOrder.ts`/`reservationPreorder
 * .ts`/`submitDineInOrder.ts` file is touched. See `docs/decisions.md`'s
 * P8-B entry for the full phase boundary.
 *
 * **Two collections, mirroring `loyaltyRewardCatalog`'s own "live doc +
 * append-only version history" pattern exactly** — the same, already-
 * accepted precedent this codebase uses everywhere a versioned, Admin-
 * mutable, customer-visible catalog is needed:
 * - `campaigns/{campaignId}` — the single current-live materialized
 *   campaign, denormalized with the full current definition for a fast
 *   one-document read. Mutable only via `campaignAdminService.ts`'s trusted
 *   operations, never a direct client write.
 * - `campaignVersions/{campaignId}_{version}` — append-only, immutable. The
 *   permanent historical record of every version of this campaign that ever
 *   existed. A redemption's own order-document snapshot
 *   ([CampaignOrderSnapshot]) additionally carries `campaignVersion` — so
 *   historical redemption never depends on either collection remaining
 *   unchanged; it is self-contained (matches `CatalogRewardOrderSnapshot`'s
 *   own established discipline exactly).
 *
 * **Flat, organizationId-scoped collection — not a nested subcollection**,
 * matching every other tenant-scoped collection in this codebase
 * (`menuProducts`/`loyaltyRewardCatalog`'s own documented precedent — no
 * nested-subcollection precedent exists anywhere in `firestore.rules`).
 * Campaign ids are Admin-chosen human-meaningful slugs, mirroring
 * `loyaltyRewardCatalog`'s own reward-id convention.
 *
 * **`active`/`archived`/`sortOrder` are deliberately NOT part of a version
 * snapshot** — exactly mirroring `loyaltyRewardCatalog.ts`'s own explicit
 * rule. Toggling active/passive or archiving a campaign never creates a new
 * version; only a change to a rule-affecting field (`title`, `description`,
 * `campaignType`, `rule`, `eligibleChannels`, `eligibleProductIds`,
 * `eligibleCategoryIds`, `minimumBasketMinorUnits`, `schedule`,
 * `usageLimit`, `perCustomerUsageLimit`) does.
 *
 * **No destructive delete, ever.** "Delete" always means
 * `active: false, archived: true` on the live doc — the doc itself, and
 * every one of its versions, is permanently retained for audit.
 *
 * **The six Admin-facing campaign types, built on one shared internal
 * mechanic × scope engine** (locked P8-A/P8-B decision — do not build six
 * independent code paths). `campaignType` is the literal, Admin-facing
 * template value; [CampaignRule] is the normalized internal representation
 * every `campaignType` maps onto. [validateCampaignTypeRuleConsistency]
 * enforces that a given `campaignType` can only ever pair with the rule
 * shape it is documented to mean — a client/Admin request that names
 * `"productDiscount"` but supplies an order-scoped rule (or vice versa) is
 * rejected, never silently reinterpreted.
 */

export const CAMPAIGNS_COLLECTION = "campaigns";
export const CAMPAIGN_VERSIONS_COLLECTION = "campaignVersions";

const CAMPAIGN_TYPES = [
  "percentageDiscount",
  "fixedAmountDiscount",
  "freeProduct",
  "buyXGetY",
  "productDiscount",
  "categoryDiscount",
] as const;
export type CampaignType = (typeof CAMPAIGN_TYPES)[number];

/**
 * The one shared internal engine every `campaignType` is normalized onto —
 * `mechanic` (the math) × `scope` (what it applies to), so `campaignPricing
 * .ts` implements exactly four mechanics once, never six parallel discount
 * calculators.
 */
export type CampaignRuleScope =
  | { kind: "order" }
  | { kind: "product"; productId: string }
  | { kind: "category"; categoryId: string };

export type CampaignRule =
  | { mechanic: "percentage"; percentBasisPoints: number; scope: CampaignRuleScope }
  | { mechanic: "fixedAmount"; amountMinorUnits: number; scope: CampaignRuleScope }
  | { mechanic: "freeProduct"; freeProductId: string }
  | {
      mechanic: "buyXGetY";
      triggerProductId: string;
      triggerQuantity: number;
      rewardProductId: string;
      rewardQuantity: number;
    };

/**
 * Enforces that `campaignType` and `rule` genuinely agree — the ONE place
 * this correspondence is checked, called from both `sanitizeCampaignRule`
 * (create/update input) and [parseCampaignDefinition] (defensive re-parse
 * of a stored document), so a malformed/tampered document can never present
 * as a type it structurally isn't.
 */
export function validateCampaignTypeRuleConsistency(campaignType: CampaignType, rule: CampaignRule): void {
  switch (campaignType) {
    case "percentageDiscount":
      if (rule.mechanic !== "percentage" || rule.scope.kind !== "order") {
        throw new RangeError('percentageDiscount requires a "percentage" rule with order scope.');
      }
      return;
    case "fixedAmountDiscount":
      if (rule.mechanic !== "fixedAmount" || rule.scope.kind !== "order") {
        throw new RangeError('fixedAmountDiscount requires a "fixedAmount" rule with order scope.');
      }
      return;
    case "freeProduct":
      if (rule.mechanic !== "freeProduct") {
        throw new RangeError('freeProduct requires a "freeProduct" rule.');
      }
      return;
    case "buyXGetY":
      if (rule.mechanic !== "buyXGetY") {
        throw new RangeError('buyXGetY requires a "buyXGetY" rule.');
      }
      return;
    case "productDiscount":
      if ((rule.mechanic !== "percentage" && rule.mechanic !== "fixedAmount") || rule.scope.kind !== "product") {
        throw new RangeError('productDiscount requires a "percentage" or "fixedAmount" rule with product scope.');
      }
      return;
    case "categoryDiscount":
      if ((rule.mechanic !== "percentage" && rule.mechanic !== "fixedAmount") || rule.scope.kind !== "category") {
        throw new RangeError('categoryDiscount requires a "percentage" or "fixedAmount" rule with category scope.');
      }
      return;
  }
}

const MAX_TITLE_LENGTH = 80;
const MAX_DESCRIPTION_LENGTH = 400;
const MAX_ELIGIBLE_IDS = 50;
const MAX_ID_LENGTH = 200;
const MAX_PERCENT_BASIS_POINTS = 10_000; // 100.00%
const MAX_AMOUNT_MINOR_UNITS = 1_000_000_00; // 1,000,000.00 TL — generous ceiling, never a silent clamp elsewhere.
const MAX_MINIMUM_BASKET_MINOR_UNITS = 1_000_000_00;
const MAX_USAGE_LIMIT = 10_000_000;
const MAX_QUANTITY = 100;
const CAMPAIGN_ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$|^[a-z0-9]$/;

/** The live, current-version campaign document — `campaigns/{campaignId}`. */
export interface CampaignDefinition {
  campaignId: string;
  organizationId: string;
  title: string;
  description: string;
  campaignType: CampaignType;
  rule: CampaignRule;
  eligibleChannels: CanonicalCommercialChannel[];
  eligibleProductIds: string[] | null;
  eligibleCategoryIds: string[] | null;
  minimumBasketMinorUnits: number | null;
  schedule: CampaignSchedule;
  usageLimit: number | null;
  perCustomerUsageLimit: number | null;
  active: boolean;
  archived: boolean;
  sortOrder: number;
  version: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/**
 * The immutable historical snapshot written to
 * `campaignVersions/{campaignId}_{version}` — deliberately excludes
 * `active`/`archived`/`sortOrder`/`updatedAt`, mirroring
 * `LoyaltyRewardCatalogVersionSnapshot`'s own exact exclusion list.
 */
export interface CampaignVersionRecord {
  campaignId: string;
  organizationId: string;
  title: string;
  description: string;
  campaignType: CampaignType;
  rule: CampaignRule;
  eligibleChannels: CanonicalCommercialChannel[];
  eligibleProductIds: string[] | null;
  eligibleCategoryIds: string[] | null;
  minimumBasketMinorUnits: number | null;
  schedule: CampaignSchedule;
  usageLimit: number | null;
  perCustomerUsageLimit: number | null;
  version: number;
  effectiveAt: Timestamp;
  createdAt: Timestamp;
}

/**
 * The one customer-facing projection — never `organizationId`/`active`/
 * `archived`/`usageLimit`/`perCustomerUsageLimit`/`createdAt`/`updatedAt`
 * (internal audit/admin/capacity provenance, not customer-facing — mirrors
 * `SanitizedCustomerLoyaltyReward`'s own exclusion list). `usageLimit`/
 * `perCustomerUsageLimit` are deliberately never exposed even as a raw
 * count — a customer never needs to know exactly how close a campaign is to
 * exhausting its cap, only whether it's currently offered to them at all.
 */
export interface SanitizedCustomerCampaign {
  campaignId: string;
  title: string;
  description: string;
  campaignType: CampaignType;
  rule: CampaignRule;
  eligibleChannels: CanonicalCommercialChannel[];
  eligibleProductIds: string[] | null;
  eligibleCategoryIds: string[] | null;
  minimumBasketMinorUnits: number | null;
  /** Wire-safe — never a raw Firestore `Timestamp` (see `sanitizeCampaignScheduleForWire`'s own doc comment). */
  schedule: SanitizedCampaignSchedule;
  sortOrder: number;
  version: number;
}

/**
 * The immutable per-order benefit snapshot — written once, at redemption
 * time, exactly like `CatalogRewardOrderSnapshot`. Preserves, at minimum,
 * every field the locked P8-A requirement named: `campaignId`,
 * `campaignVersion`, `title`, `campaignType`, `appliedRule`, `appliedValue`,
 * `discountMinorUnits`, `orderChannel`. A later live edit to the campaign
 * (even a full version bump) never rewrites an already-placed order's own
 * history — old orders never re-read live campaign data.
 *
 * **Not yet written by any order-submission path (P8-B is foundation
 * only)** — this type exists so a future checkout-integration phase has an
 * exact, already-reviewed target shape to write into, never an
 * ad hoc/improvised one at that time.
 */
export interface CampaignOrderSnapshot {
  campaignId: string;
  campaignVersion: number;
  title: string;
  campaignType: CampaignType;
  appliedRule: CampaignRule;
  appliedValue: number;
  discountMinorUnits: number;
  orderChannel: CanonicalCommercialChannel;
}

export function campaignVersionDocId(campaignId: string, version: number): string {
  return `${campaignId}_${version}`;
}

export function sanitizeCampaignId(raw: unknown): string {
  if (typeof raw !== "string" || !CAMPAIGN_ID_PATTERN.test(raw)) {
    throw new RangeError("campaignId must be a lowercase alphanumeric-and-hyphen slug (2-64 chars, no leading/trailing hyphen).");
  }
  return raw;
}

export function sanitizeCampaignTitle(raw: unknown): string {
  if (typeof raw !== "string") throw new RangeError("title must be a string.");
  const trimmed = raw.trim();
  if (trimmed.length === 0) throw new RangeError("title must not be empty.");
  if (trimmed.length > MAX_TITLE_LENGTH) throw new RangeError("title is too long.");
  return trimmed;
}

export function sanitizeCampaignDescription(raw: unknown): string {
  if (typeof raw !== "string") throw new RangeError("description must be a string.");
  const trimmed = raw.trim();
  if (trimmed.length === 0) throw new RangeError("description must not be empty.");
  if (trimmed.length > MAX_DESCRIPTION_LENGTH) throw new RangeError("description is too long.");
  return trimmed;
}

export function sanitizeCampaignType(raw: unknown): CampaignType {
  if (typeof raw !== "string" || !(CAMPAIGN_TYPES as readonly string[]).includes(raw)) {
    throw new RangeError(`campaignType must be one of: ${CAMPAIGN_TYPES.join(", ")}.`);
  }
  return raw as CampaignType;
}

/** Required, non-empty, canonical-order-normalized — reuses `loyaltyRewardCatalog.ts`'s own `CANONICAL_COMMERCIAL_CHANNELS` vocabulary verbatim (the shared boundary that constant was created for, per its own P7-C.1 doc comment). */
export function sanitizeCampaignEligibleChannels(raw: unknown): CanonicalCommercialChannel[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new RangeError("eligibleChannels must be a non-empty array.");
  }
  const seen = new Set<CanonicalCommercialChannel>();
  for (const entry of raw) {
    if (typeof entry !== "string" || !(CANONICAL_COMMERCIAL_CHANNELS as readonly string[]).includes(entry)) {
      throw new RangeError(`eligibleChannels entries must each be one of: ${CANONICAL_COMMERCIAL_CHANNELS.join(", ")}.`);
    }
    seen.add(entry as CanonicalCommercialChannel);
  }
  return CANONICAL_COMMERCIAL_CHANNELS.filter((channel) => seen.has(channel));
}

function sanitizeIdArray(raw: unknown, fieldName: string): string[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new RangeError(`${fieldName} must be a non-empty array when present.`);
  }
  if (raw.length > MAX_ELIGIBLE_IDS) {
    throw new RangeError(`${fieldName} has too many entries.`);
  }
  const seen = new Set<string>();
  const result: string[] = [];
  for (const entry of raw) {
    if (typeof entry !== "string" || entry.trim().length === 0) {
      throw new RangeError(`every ${fieldName} entry must be a non-empty string.`);
    }
    if (entry.length > MAX_ID_LENGTH) {
      throw new RangeError(`an ${fieldName} entry is too long.`);
    }
    if (!seen.has(entry)) {
      seen.add(entry);
      result.push(entry);
    }
  }
  return result;
}

/** `null`/`undefined` both mean "no product targeting" (order-wide campaign) — collapses to `null`. */
export function sanitizeOptionalEligibleProductIds(raw: unknown): string[] | null {
  if (raw === null || raw === undefined) return null;
  return sanitizeIdArray(raw, "eligibleProductIds");
}

/** `null`/`undefined` both mean "no category targeting" — collapses to `null`. Existence/tenant-ownership of each id is validated separately, transactionally, in `campaignAdminService.ts` — this only validates SHAPE. */
export function sanitizeOptionalEligibleCategoryIds(raw: unknown): string[] | null {
  if (raw === null || raw === undefined) return null;
  return sanitizeIdArray(raw, "eligibleCategoryIds");
}

export function sanitizeOptionalMinimumBasketMinorUnits(raw: unknown): number | null {
  if (raw === null || raw === undefined) return null;
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 0 || raw > MAX_MINIMUM_BASKET_MINOR_UNITS) {
    throw new RangeError("minimumBasketMinorUnits must be a non-negative integer or null.");
  }
  return raw;
}

export function sanitizeOptionalUsageLimit(raw: unknown, fieldName: string): number | null {
  if (raw === null || raw === undefined) return null;
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0 || raw > MAX_USAGE_LIMIT) {
    throw new RangeError(`${fieldName} must be a positive integer or null.`);
  }
  return raw;
}

function sanitizePercentBasisPoints(raw: unknown): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0 || raw > MAX_PERCENT_BASIS_POINTS) {
    throw new RangeError("percentBasisPoints must be a positive integer no greater than 10000 (100%).");
  }
  return raw;
}

function sanitizeAmountMinorUnits(raw: unknown): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0 || raw > MAX_AMOUNT_MINOR_UNITS) {
    throw new RangeError("amountMinorUnits must be a positive integer.");
  }
  return raw;
}

function sanitizeProductId(raw: unknown, fieldName: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0 || raw.length > MAX_ID_LENGTH) {
    throw new RangeError(`${fieldName} must be a non-empty string.`);
  }
  return raw;
}

function sanitizeQuantity(raw: unknown, fieldName: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0 || raw > MAX_QUANTITY) {
    throw new RangeError(`${fieldName} must be a positive integer.`);
  }
  return raw;
}

function sanitizeRuleScope(raw: unknown): CampaignRuleScope {
  if (typeof raw !== "object" || raw === null) {
    throw new RangeError("scope must be an object.");
  }
  const kind = (raw as Record<string, unknown>).kind;
  if (kind === "order") return { kind: "order" };
  if (kind === "product") {
    return { kind: "product", productId: sanitizeProductId((raw as Record<string, unknown>).productId, "scope.productId") };
  }
  if (kind === "category") {
    return { kind: "category", categoryId: sanitizeProductId((raw as Record<string, unknown>).categoryId, "scope.categoryId") };
  }
  throw new RangeError('scope.kind must be one of: "order", "product", "category".');
}

/** Validates SHAPE only — [validateCampaignTypeRuleConsistency] must be called separately (by the caller, which knows `campaignType`) to confirm the rule actually matches the declared type. */
export function sanitizeCampaignRule(raw: unknown): CampaignRule {
  if (typeof raw !== "object" || raw === null) {
    throw new RangeError("rule must be an object.");
  }
  const data = raw as Record<string, unknown>;
  switch (data.mechanic) {
    case "percentage":
      return {
        mechanic: "percentage",
        percentBasisPoints: sanitizePercentBasisPoints(data.percentBasisPoints),
        scope: sanitizeRuleScope(data.scope),
      };
    case "fixedAmount":
      return {
        mechanic: "fixedAmount",
        amountMinorUnits: sanitizeAmountMinorUnits(data.amountMinorUnits),
        scope: sanitizeRuleScope(data.scope),
      };
    case "freeProduct":
      return {
        mechanic: "freeProduct",
        freeProductId: sanitizeProductId(data.freeProductId, "rule.freeProductId"),
      };
    case "buyXGetY":
      return {
        mechanic: "buyXGetY",
        triggerProductId: sanitizeProductId(data.triggerProductId, "rule.triggerProductId"),
        triggerQuantity: sanitizeQuantity(data.triggerQuantity, "rule.triggerQuantity"),
        rewardProductId: sanitizeProductId(data.rewardProductId, "rule.rewardProductId"),
        rewardQuantity: sanitizeQuantity(data.rewardQuantity, "rule.rewardQuantity"),
      };
    default:
      throw new RangeError('rule.mechanic must be one of: "percentage", "fixedAmount", "freeProduct", "buyXGetY".');
  }
}

/** Every product/category id a rule can name, for the caller to validate existence/tenant-ownership against canonical `menuProducts`. */
export function ruleReferencedProductIds(rule: CampaignRule): string[] {
  switch (rule.mechanic) {
    case "percentage":
    case "fixedAmount":
      return rule.scope.kind === "product" ? [rule.scope.productId] : [];
    case "freeProduct":
      return [rule.freeProductId];
    case "buyXGetY":
      return [rule.triggerProductId, rule.rewardProductId];
  }
}

export function ruleReferencedCategoryIds(rule: CampaignRule): string[] {
  if ((rule.mechanic === "percentage" || rule.mechanic === "fixedAmount") && rule.scope.kind === "category") {
    return [rule.scope.categoryId];
  }
  return [];
}

/**
 * Trusted server-time validity check — active, non-archived, currently
 * within its schedule. Never evaluated against client-supplied time; every
 * caller passes a server-derived `now` and a trusted `timeZone` (see
 * `campaignScheduling.ts`'s own doc comment on where `timeZone` should come
 * from).
 */
export function isCampaignCurrentlyEligible(
  campaign: Pick<CampaignDefinition, "active" | "archived" | "schedule">,
  now: Timestamp,
  timeZone: string,
): boolean {
  if (!campaign.active || campaign.archived) return false;
  return isCampaignScheduleCurrentlyOpen(campaign.schedule, now, timeZone);
}

export function sanitizeCustomerCampaign(campaign: CampaignDefinition): SanitizedCustomerCampaign {
  return {
    campaignId: campaign.campaignId,
    title: campaign.title,
    description: campaign.description,
    campaignType: campaign.campaignType,
    rule: campaign.rule,
    eligibleChannels: campaign.eligibleChannels,
    eligibleProductIds: campaign.eligibleProductIds,
    eligibleCategoryIds: campaign.eligibleCategoryIds,
    minimumBasketMinorUnits: campaign.minimumBasketMinorUnits,
    schedule: sanitizeCampaignScheduleForWire(campaign.schedule),
    sortOrder: campaign.sortOrder,
    version: campaign.version,
  };
}

/**
 * Defensive parse of a raw Firestore document into a [CampaignDefinition] —
 * returns `null` (never throws) on any malformed/corrupt shape, mirroring
 * `parseLoyaltyRewardCatalogEntry`'s own fail-closed-by-exclusion
 * discipline.
 */
export function parseCampaignDefinition(raw: FirebaseFirestore.DocumentData | undefined): CampaignDefinition | null {
  if (!raw) return null;
  try {
    const campaignId = sanitizeCampaignId(raw.campaignId);
    const organizationId = raw.organizationId;
    if (typeof organizationId !== "string" || organizationId.length === 0) return null;
    const title = sanitizeCampaignTitle(raw.title);
    const description = sanitizeCampaignDescription(raw.description);
    const campaignType = sanitizeCampaignType(raw.campaignType);
    const rule = sanitizeCampaignRule(raw.rule);
    validateCampaignTypeRuleConsistency(campaignType, rule);
    const eligibleChannels = sanitizeCampaignEligibleChannels(raw.eligibleChannels);
    const eligibleProductIds = sanitizeOptionalEligibleProductIds(raw.eligibleProductIds);
    const eligibleCategoryIds = sanitizeOptionalEligibleCategoryIds(raw.eligibleCategoryIds);
    const minimumBasketMinorUnits = sanitizeOptionalMinimumBasketMinorUnits(raw.minimumBasketMinorUnits);
    const schedule = sanitizeCampaignSchedule(raw.schedule);
    const usageLimit = sanitizeOptionalUsageLimit(raw.usageLimit, "usageLimit");
    const perCustomerUsageLimit = sanitizeOptionalUsageLimit(raw.perCustomerUsageLimit, "perCustomerUsageLimit");
    const sortOrder = sanitizeSortOrder(raw.sortOrder);
    if (typeof raw.active !== "boolean" || typeof raw.archived !== "boolean") return null;
    if (typeof raw.version !== "number" || !Number.isInteger(raw.version) || raw.version <= 0) return null;
    if (!(raw.createdAt instanceof Timestamp) || !(raw.updatedAt instanceof Timestamp)) return null;
    return {
      campaignId,
      organizationId,
      title,
      description,
      campaignType,
      rule,
      eligibleChannels,
      eligibleProductIds,
      eligibleCategoryIds,
      minimumBasketMinorUnits,
      schedule,
      usageLimit,
      perCustomerUsageLimit,
      active: raw.active,
      archived: raw.archived,
      sortOrder,
      version: raw.version,
      createdAt: raw.createdAt,
      updatedAt: raw.updatedAt,
    };
  } catch {
    return null;
  }
}

// Re-exported so callers of this module never need a second import line
// for the validity-window helper `sanitizeCampaignSchedule` itself already
// depends on.
export { sanitizeOptionalTimestamp, validateValidityWindow };
