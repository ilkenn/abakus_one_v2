import { Timestamp } from "firebase-admin/firestore";

/**
 * `loyaltyRewardCatalog` — Boncuk Loyalty Program P7-B (2026-08-24).
 *
 * Server-authoritative foundation for the Reward Catalog (BR-LOYALTY-007):
 * customers exchanging Boncuk for a specific, explicitly defined reward —
 * distinct from cash-value redemption (`loyaltyRedemption.ts`) against an
 * order total. This file is the pure domain module: types, sanitizers,
 * parsing, and validity evaluation — no Firestore I/O, no transaction
 * logic (see `loyaltyRewardCatalogAdminService.ts` for the trusted write
 * operations, `resolveCatalogRewardRedemption.ts` for the pure redemption
 * calculator).
 *
 * **Two collections, mirroring `loyaltyPolicy.ts`'s own already-accepted
 * "live doc + append-only version history" pattern exactly** (P7-A audit
 * finding: this is the closest, most directly reusable precedent in the
 * codebase for "should reward versions live in a separate collection or be
 * snapshotted only on redemption" — the answer, matching `loyaltyPolicy.ts`,
 * is both):
 * - `loyaltyRewardCatalog/{rewardId}` — the single current-live materialized
 *   reward, denormalized with the full current definition for a fast
 *   one-document read. Mutable only via `loyaltyRewardCatalogAdminService
 *   .ts`'s trusted operations, never a direct client write.
 * - `loyaltyRewardCatalogVersions/{rewardId}_{version}` — append-only,
 *   immutable. The permanent historical record of every version of this
 *   reward that ever existed, at what cost, for what products, from when.
 *   A redemption's own order-document snapshot (P7-C, not built yet) will
 *   additionally carry `rewardVersion` — so historical redemption never
 *   depends on either collection remaining unchanged; it is self-contained.
 *
 * **Flat, composite-scoped collections — not nested subcollections.** The
 * P7-A audit confirmed zero nested-subcollection precedent exists anywhere
 * in `firestore.rules`; every tenant-scoped collection in this codebase is
 * a flat top-level collection with an `organizationId` field (`menuProducts`'
 * own shape) or a `{organizationId}_{id}` composite doc id
 * (`loyaltyAccounts`/`tenantCustomers`). Reward ids are meaningful,
 * human-chosen slugs (e.g. `"icecek"`) rather than a composite id, mirroring
 * `reservationAreas`' own precedent (`"garden"`/`"indoor"`) — organizationId
 * lives as a field, queried the same way `menuProducts` already is.
 *
 * **`rewardType` — MVP is `"explicitProductSet"` only, deliberately.** The
 * P7-A audit found real, current price spread within a single menu category
 * (bowl: 430–800 TL) that would let a customer systematically pick the most
 * expensive eligible item under a category-level entitlement — a real
 * arbitrage/economics risk. P7-B's locked instruction is explicit: no
 * category-based automatic eligibility this phase. `rewardType` is still a
 * discriminated union (not a bare string) so a future `"categoryWithCap"`
 * variant can be added additively, without a breaking change to this type.
 *
 * **`active`/`archived` are deliberately NOT part of a version snapshot.**
 * The locked instruction lists exactly what requires a new version —
 * `boncukCost`, `eligibleProductIds`, `title`/`description`, validity
 * window — and does not include `active`/`archived`. These are live
 * operational status flags, not part of the reward's historical DEFINITION;
 * toggling them never creates a new version (see
 * `loyaltyRewardCatalogAdminService.ts`'s `setLoyaltyRewardActive`/
 * `archiveLoyaltyReward`, which mutate the live doc directly).
 *
 * **No destructive delete, ever.** "Delete" always means
 * `active: false, archived: true` on the live doc — the doc itself, and
 * every one of its versions, is permanently retained for audit.
 */

export const LOYALTY_REWARD_CATALOG_COLLECTION = "loyaltyRewardCatalog";
export const LOYALTY_REWARD_CATALOG_VERSIONS_COLLECTION = "loyaltyRewardCatalogVersions";

// Closed union, additively extensible — see this file's own doc comment.
const LOYALTY_REWARD_TYPES = ["explicitProductSet"] as const;
export type LoyaltyRewardType = (typeof LOYALTY_REWARD_TYPES)[number];

/**
 * `CANONICAL_COMMERCIAL_CHANNELS` — Boncuk Loyalty Program P7-C.1
 * (2026-08-24).
 *
 * **The shared channel vocabulary boundary between the Reward Catalog and
 * the future Campaign Engine.** Deliberately named/placed independent of
 * "reward" — a future `campaignEngine.ts` module imports this SAME constant
 * rather than declaring a parallel one, so "delivery only" / "takeaway
 * only" / "dineIn + takeaway" / "reservationPreorder only" / "all channels"
 * mean identically the same thing in both domains. This phase does not
 * build the Campaign Engine itself (still out of scope) — this constant is
 * the one piece of it locked in now, per the explicit instruction to
 * document only the shared vocabulary/interface boundary.
 *
 * **Deliberately NOT the same vocabulary as a real order's own `channel`
 * field.** `Order.channel` (`submitTakeawayOrder.ts`/`submitDeliveryOrder
 * .ts`/`reservationPreorder.ts`) is a raw, already-more-granular set of
 * literal values (`"takeaway"`/`"delivery"`/`"reservationPreorder"`/
 * `"dineInQr"`/`"dineInStaff"`) — the reward/campaign vocabulary is a
 * coarser, customer/Admin-facing abstraction where both `dineInQr` and
 * `dineInStaff` collapse into a single `"dineIn"` commercial concept.
 * `"takeaway"`/`"delivery"`/`"reservationPreorder"` happen to be spelled
 * identically in both vocabularies (no translation needed at the one
 * checkout-validation site that exists this phase — `submitTakeawayOrder
 * .ts` checks `eligibleChannels.includes("takeaway")` directly against the
 * order's own real channel), but `"dineIn"` has no direct `Order.channel`
 * counterpart yet; mapping it to a real dine-in order's own channel is a
 * problem for whichever future phase wires dine-in reward redemption, not
 * this one.
 */
export const CANONICAL_COMMERCIAL_CHANNELS = [
  "dineIn",
  "takeaway",
  "delivery",
  "reservationPreorder",
] as const;
export type CanonicalCommercialChannel = (typeof CANONICAL_COMMERCIAL_CHANNELS)[number];

const MAX_TITLE_LENGTH = 80;
const MAX_DESCRIPTION_LENGTH = 400;
const MAX_ELIGIBLE_PRODUCT_IDS = 50;
const MAX_PRODUCT_ID_LENGTH = 200;
const MAX_BONCUK_COST = 1_000_000;
const MAX_SORT_ORDER = 100_000;
const REWARD_ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$|^[a-z0-9]$/;

/** The live, current-version reward document — `loyaltyRewardCatalog/{rewardId}`. */
export interface LoyaltyRewardCatalogEntry {
  rewardId: string;
  organizationId: string;
  title: string;
  description: string;
  rewardType: LoyaltyRewardType;
  eligibleProductIds: string[];
  /** P7-C.1 — required, non-empty, deduped, canonical-order-normalized. Changing this creates a new immutable version (part of the versioned definition, unlike `active`/`archived`). */
  eligibleChannels: CanonicalCommercialChannel[];
  boncukCost: number;
  active: boolean;
  archived: boolean;
  sortOrder: number;
  version: number;
  validFrom: Timestamp | null;
  validUntil: Timestamp | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

/**
 * The immutable historical snapshot written to
 * `loyaltyRewardCatalogVersions/{rewardId}_{version}` — the full definition
 * needed to reconstruct historical eligibility/cost, deliberately excluding
 * `active`/`archived` (operational status, not part of the definition — see
 * this file's own doc comment) and `updatedAt` (a version, once written,
 * is never updated).
 */
export interface LoyaltyRewardCatalogVersionSnapshot {
  rewardId: string;
  organizationId: string;
  title: string;
  description: string;
  rewardType: LoyaltyRewardType;
  eligibleProductIds: string[];
  eligibleChannels: CanonicalCommercialChannel[];
  boncukCost: number;
  sortOrder: number;
  version: number;
  validFrom: Timestamp | null;
  validUntil: Timestamp | null;
  effectiveAt: Timestamp;
  createdAt: Timestamp;
}

/**
 * The one customer-facing projection — never `organizationId`/`active`/
 * `archived`/`validFrom`/`validUntil`/`createdAt`/`updatedAt` (internal
 * audit/admin provenance, not customer-facing). A reward this callable ever
 * returns is, by construction, already active/non-archived/currently valid
 * for the caller's own tenant — the client never needs to re-derive that.
 */
export interface SanitizedCustomerLoyaltyReward {
  rewardId: string;
  title: string;
  description: string;
  rewardType: LoyaltyRewardType;
  eligibleProductIds: string[];
  eligibleChannels: CanonicalCommercialChannel[];
  boncukCost: number;
  sortOrder: number;
  version: number;
}

export function loyaltyRewardCatalogVersionDocId(rewardId: string, version: number): string {
  return `${rewardId}_${version}`;
}

export function sanitizeRewardId(raw: unknown): string {
  if (typeof raw !== "string" || !REWARD_ID_PATTERN.test(raw)) {
    throw new RangeError(
      "rewardId must be a lowercase alphanumeric-and-hyphen slug (2-64 chars, no leading/trailing hyphen).",
    );
  }
  return raw;
}

export function sanitizeRewardTitle(raw: unknown): string {
  if (typeof raw !== "string") throw new RangeError("title must be a string.");
  const trimmed = raw.trim();
  if (trimmed.length === 0) throw new RangeError("title must not be empty.");
  if (trimmed.length > MAX_TITLE_LENGTH) throw new RangeError("title is too long.");
  return trimmed;
}

export function sanitizeRewardDescription(raw: unknown): string {
  if (typeof raw !== "string") throw new RangeError("description must be a string.");
  const trimmed = raw.trim();
  if (trimmed.length === 0) throw new RangeError("description must not be empty.");
  if (trimmed.length > MAX_DESCRIPTION_LENGTH) throw new RangeError("description is too long.");
  return trimmed;
}

export function sanitizeRewardType(raw: unknown): LoyaltyRewardType {
  if (typeof raw !== "string" || !(LOYALTY_REWARD_TYPES as readonly string[]).includes(raw)) {
    throw new RangeError(`rewardType must be one of: ${LOYALTY_REWARD_TYPES.join(", ")}.`);
  }
  return raw as LoyaltyRewardType;
}

/** Non-empty, bounded, de-duplicated, each entry a non-empty bounded-length string. Existence/tenant-ownership of each id is validated separately, transactionally, against real `menuProducts` — this only validates SHAPE. */
export function sanitizeEligibleProductIds(raw: unknown): string[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new RangeError("eligibleProductIds must be a non-empty array.");
  }
  if (raw.length > MAX_ELIGIBLE_PRODUCT_IDS) {
    throw new RangeError("eligibleProductIds has too many entries.");
  }
  const seen = new Set<string>();
  const result: string[] = [];
  for (const entry of raw) {
    if (typeof entry !== "string" || entry.trim().length === 0) {
      throw new RangeError("every eligibleProductIds entry must be a non-empty string.");
    }
    if (entry.length > MAX_PRODUCT_ID_LENGTH) {
      throw new RangeError("an eligibleProductIds entry is too long.");
    }
    if (!seen.has(entry)) {
      seen.add(entry);
      result.push(entry);
    }
  }
  return result;
}

/**
 * Required, non-empty, only-canonical-values, deterministically normalized
 * (P7-C.1 — "duplicate channels rejected or normalized deterministically";
 * this sanitizer normalizes, mirroring `sanitizeEligibleProductIds`'s own
 * dedupe-rather-than-reject convention). The returned array is ALWAYS
 * emitted in `CANONICAL_COMMERCIAL_CHANNELS`'s own fixed order — never
 * insertion order — so two requests describing the same channel SET in a
 * different order, or with duplicates, produce a byte-identical stored
 * array. Throws on any entry outside the closed vocabulary — a client can
 * never invent a fifth channel.
 */
export function sanitizeEligibleChannels(raw: unknown): CanonicalCommercialChannel[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new RangeError("eligibleChannels must be a non-empty array.");
  }
  const seen = new Set<CanonicalCommercialChannel>();
  for (const entry of raw) {
    if (typeof entry !== "string" || !(CANONICAL_COMMERCIAL_CHANNELS as readonly string[]).includes(entry)) {
      throw new RangeError(
        `eligibleChannels entries must each be one of: ${CANONICAL_COMMERCIAL_CHANNELS.join(", ")}.`,
      );
    }
    seen.add(entry as CanonicalCommercialChannel);
  }
  return CANONICAL_COMMERCIAL_CHANNELS.filter((channel) => seen.has(channel));
}

export function sanitizeBoncukCost(raw: unknown): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0 || raw > MAX_BONCUK_COST) {
    throw new RangeError("boncukCost must be a positive integer.");
  }
  return raw;
}

export function sanitizeSortOrder(raw: unknown): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 0 || raw > MAX_SORT_ORDER) {
    throw new RangeError("sortOrder must be a non-negative integer.");
  }
  return raw;
}

/** `null`/`undefined` both mean "no boundary on this side" — the caller decides which sentinel it prefers to send; both collapse to `null` here. */
export function sanitizeOptionalTimestamp(raw: unknown, fieldName: string): Timestamp | null {
  if (raw === null || raw === undefined) return null;
  if (raw instanceof Timestamp) return raw;
  if (raw instanceof Date) return Timestamp.fromDate(raw);
  throw new RangeError(`${fieldName} must be a Timestamp/Date or null.`);
}

export function validateValidityWindow(validFrom: Timestamp | null, validUntil: Timestamp | null): void {
  if (validFrom !== null && validUntil !== null && !(validFrom.toMillis() < validUntil.toMillis())) {
    throw new RangeError("validFrom must be strictly before validUntil when both are present.");
  }
}

/**
 * Trusted server-time validity check — active, non-archived, within the
 * validity window. Never evaluated against client-supplied time; every
 * caller passes a server-derived `now` (`Timestamp.now()` inside a
 * transaction, or the callable's own server clock).
 */
export function isRewardCurrentlyValid(
  reward: Pick<LoyaltyRewardCatalogEntry, "active" | "archived" | "validFrom" | "validUntil">,
  now: Timestamp,
): boolean {
  if (!reward.active || reward.archived) return false;
  if (reward.validFrom !== null && now.toMillis() < reward.validFrom.toMillis()) return false;
  if (reward.validUntil !== null && now.toMillis() >= reward.validUntil.toMillis()) return false;
  return true;
}

/**
 * Defensive parse of a raw Firestore document into a
 * [LoyaltyRewardCatalogEntry] — returns `null` (never throws) on any
 * malformed/corrupt shape, so a caller can fail closed by simply excluding
 * the entry (customer-facing read) or treating it as not-found (redemption
 * resolver's loader), never crashing on a single bad document.
 */
export function parseLoyaltyRewardCatalogEntry(
  raw: FirebaseFirestore.DocumentData | undefined,
): LoyaltyRewardCatalogEntry | null {
  if (!raw) return null;
  try {
    const rewardId = sanitizeRewardId(raw.rewardId);
    const organizationId = raw.organizationId;
    if (typeof organizationId !== "string" || organizationId.length === 0) return null;
    const title = sanitizeRewardTitle(raw.title);
    const description = sanitizeRewardDescription(raw.description);
    const rewardType = sanitizeRewardType(raw.rewardType);
    const eligibleProductIds = sanitizeEligibleProductIds(raw.eligibleProductIds);
    const eligibleChannels = sanitizeEligibleChannels(raw.eligibleChannels);
    const boncukCost = sanitizeBoncukCost(raw.boncukCost);
    const sortOrder = sanitizeSortOrder(raw.sortOrder);
    if (typeof raw.active !== "boolean" || typeof raw.archived !== "boolean") return null;
    if (typeof raw.version !== "number" || !Number.isInteger(raw.version) || raw.version <= 0) return null;
    const validFrom = sanitizeOptionalTimestamp(raw.validFrom, "validFrom");
    const validUntil = sanitizeOptionalTimestamp(raw.validUntil, "validUntil");
    validateValidityWindow(validFrom, validUntil);
    if (!(raw.createdAt instanceof Timestamp) || !(raw.updatedAt instanceof Timestamp)) return null;
    return {
      rewardId,
      organizationId,
      title,
      description,
      rewardType,
      eligibleProductIds,
      eligibleChannels,
      boncukCost,
      active: raw.active,
      archived: raw.archived,
      sortOrder,
      version: raw.version,
      validFrom,
      validUntil,
      createdAt: raw.createdAt,
      updatedAt: raw.updatedAt,
    };
  } catch {
    return null;
  }
}

export function sanitizeCustomerLoyaltyReward(
  reward: LoyaltyRewardCatalogEntry,
): SanitizedCustomerLoyaltyReward {
  return {
    rewardId: reward.rewardId,
    title: reward.title,
    description: reward.description,
    rewardType: reward.rewardType,
    eligibleProductIds: reward.eligibleProductIds,
    eligibleChannels: reward.eligibleChannels,
    boncukCost: reward.boncukCost,
    sortOrder: reward.sortOrder,
    version: reward.version,
  };
}
