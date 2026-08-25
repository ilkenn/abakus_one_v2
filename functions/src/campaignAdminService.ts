import { Timestamp, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { loadCanonicalMenuProduct } from "./takeawayCatalog";
import { sanitizeSortOrder } from "./loyaltyRewardCatalog";
import {
  CAMPAIGNS_COLLECTION,
  CAMPAIGN_VERSIONS_COLLECTION,
  campaignVersionDocId,
  sanitizeCampaignId,
  sanitizeCampaignTitle,
  sanitizeCampaignDescription,
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
  type CampaignDefinition,
  type CampaignVersionRecord,
  type CampaignType,
  type CampaignRule,
} from "./campaignEngine";
import { sanitizeCampaignSchedule, type CampaignSchedule } from "./campaignScheduling";

/**
 * `campaignAdminService` — Server-Authoritative Campaign Engine P8-B
 * (2026-08-25).
 *
 * Trusted service/domain operations for managing Campaigns — **not Cloud
 * Function callables**, mirroring `loyaltyRewardCatalogAdminService.ts`'s
 * own explicit, deliberate shape and its own reasoning verbatim: every
 * operation here is a plain, directly-importable async function, callable
 * today only from a trusted Admin-SDK context (a dev-seed script, or a
 * future real Admin-authorized `onCall` wrapper that does nothing more than
 * authenticate/authorize the caller and forward validated input here — no
 * redesign needed when that phase arrives). No Admin UI, no new
 * `StaffPermission`, no `onCall` wrapper this phase — inventing a
 * permission before any real Admin screen consumes it would be exactly the
 * "premature permission/UI scope" `loyaltyRewardCatalogAdminService.ts`'s
 * own P7-B instruction warned against, and the SAME reasoning applies here.
 *
 * **Every operation manages its own transaction** (never accepts a
 * caller-supplied `tx`) — these are top-level trusted operations, not
 * composed into a larger transaction, mirroring
 * `loyaltyRewardCatalogAdminService.ts`'s own exact shape.
 */

function organizationRef(db: Firestore, organizationId: string) {
  return db.collection("organizations").doc(organizationId);
}

function campaignRef(db: Firestore, campaignId: string) {
  return db.collection(CAMPAIGNS_COLLECTION).doc(campaignId);
}

function campaignVersionRef(db: Firestore, campaignId: string, version: number) {
  return db.collection(CAMPAIGN_VERSIONS_COLLECTION).doc(campaignVersionDocId(campaignId, version));
}

async function requireActiveOrganizationInTransaction(
  tx: FirebaseFirestore.Transaction,
  db: Firestore,
  organizationId: string,
): Promise<void> {
  const orgSnap = await tx.get(organizationRef(db, organizationId));
  if (!orgSnap.exists) {
    throw new HttpsError("failed-precondition", `Organization "${organizationId}" does not exist.`);
  }
  if (orgSnap.data()!.isActive !== true) {
    throw new HttpsError("failed-precondition", `Organization "${organizationId}" is not active.`);
  }
}

/**
 * Validates every product id a rule references exists in the real canonical
 * `menuProducts` collection and belongs to `organizationId` — never accepts
 * a client/caller-asserted product as proof of eligibility. This is what
 * structurally excludes a Bowl Builder line's own ad hoc `custom_bowl_...`
 * id (locked decision: "Product/category campaigns must NOT use fake Bowl
 * Builder product IDs") — such an id can never exist in `menuProducts`, so
 * it can never pass this check.
 */
async function requireEligibleCanonicalProductsInTransaction(
  tx: FirebaseFirestore.Transaction,
  db: Firestore,
  organizationId: string,
  productIds: readonly string[],
): Promise<void> {
  for (const productId of productIds) {
    const product = await loadCanonicalMenuProduct(db, productId, tx);
    if (!product) {
      throw new HttpsError("failed-precondition", `Eligible product "${productId}" does not exist.`);
    }
    if (product.organizationId !== organizationId) {
      throw new HttpsError(
        "failed-precondition",
        `Eligible product "${productId}" does not belong to organization "${organizationId}".`,
      );
    }
  }
}

/**
 * No canonical `menuCategories` collection exists anywhere in this codebase
 * (confirmed by audit — `categoryId` is only ever a plain field on a
 * `menuProducts` document, never a first-class entity). A category "exists"
 * for this purpose exactly when at least one real, org-scoped
 * `menuProducts` document currently carries it — the only honest existence
 * check available, and one that (like the product check above) structurally
 * excludes any Bowl Builder-shaped fake id. Equality-only filters
 * (`organizationId==`, `categoryId==`) — no composite index required,
 * mirroring `getCustomerLoyaltyRewardCatalog.ts`'s own documented reasoning
 * for why its own equality-only query needs none either.
 */
async function requireEligibleCanonicalCategoriesInTransaction(
  tx: FirebaseFirestore.Transaction,
  db: Firestore,
  organizationId: string,
  categoryIds: readonly string[],
): Promise<void> {
  for (const categoryId of categoryIds) {
    const querySnap = await tx.get(
      db
        .collection("menuProducts")
        .where("organizationId", "==", organizationId)
        .where("categoryId", "==", categoryId)
        .limit(1),
    );
    if (querySnap.empty) {
      throw new HttpsError(
        "failed-precondition",
        `Eligible category "${categoryId}" does not exist for organization "${organizationId}".`,
      );
    }
  }
}

async function requireEligibleTargetsInTransaction(
  tx: FirebaseFirestore.Transaction,
  db: Firestore,
  organizationId: string,
  rule: CampaignRule,
  eligibleProductIds: string[] | null,
  eligibleCategoryIds: string[] | null,
): Promise<void> {
  const productIds = new Set<string>([...ruleReferencedProductIds(rule), ...(eligibleProductIds ?? [])]);
  const categoryIds = new Set<string>([...ruleReferencedCategoryIds(rule), ...(eligibleCategoryIds ?? [])]);
  await requireEligibleCanonicalProductsInTransaction(tx, db, organizationId, Array.from(productIds));
  await requireEligibleCanonicalCategoriesInTransaction(tx, db, organizationId, Array.from(categoryIds));
}

export interface CreateCampaignInput {
  organizationId: string;
  campaignId: string;
  title: string;
  description: string;
  campaignType: CampaignType;
  rule: unknown;
  eligibleChannels: string[];
  eligibleProductIds?: unknown;
  eligibleCategoryIds?: unknown;
  minimumBasketMinorUnits?: unknown;
  schedule: unknown;
  usageLimit?: unknown;
  perCustomerUsageLimit?: unknown;
  sortOrder: number;
}

export interface CreateCampaignResult {
  campaignId: string;
  version: number;
  created: boolean;
}

/**
 * Idempotent by design: if `campaignId` already exists, this is a safe
 * no-op returning the existing live version untouched — `created: false`.
 * Deliberately NOT "upsert" — a genuine field change must go through
 * [updateCampaignByCreatingNextVersion] instead, mirroring
 * `createLoyaltyReward`'s own exact discipline.
 */
export async function createCampaign(db: Firestore, input: CreateCampaignInput): Promise<CreateCampaignResult> {
  const organizationId = input.organizationId;
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    throw new HttpsError("invalid-argument", "organizationId is required.");
  }
  const campaignId = sanitizeCampaignId(input.campaignId);
  const title = sanitizeCampaignTitle(input.title);
  const description = sanitizeCampaignDescription(input.description);
  const campaignType = sanitizeCampaignType(input.campaignType);
  const rule = sanitizeCampaignRule(input.rule);
  validateCampaignTypeRuleConsistency(campaignType, rule);
  const eligibleChannels = sanitizeCampaignEligibleChannels(input.eligibleChannels);
  const eligibleProductIds = sanitizeOptionalEligibleProductIds(input.eligibleProductIds);
  const eligibleCategoryIds = sanitizeOptionalEligibleCategoryIds(input.eligibleCategoryIds);
  const minimumBasketMinorUnits = sanitizeOptionalMinimumBasketMinorUnits(input.minimumBasketMinorUnits);
  const schedule = sanitizeCampaignSchedule(input.schedule);
  const usageLimit = sanitizeOptionalUsageLimit(input.usageLimit, "usageLimit");
  const perCustomerUsageLimit = sanitizeOptionalUsageLimit(input.perCustomerUsageLimit, "perCustomerUsageLimit");
  const sortOrder = sanitizeSortOrder(input.sortOrder);

  return db.runTransaction(async (tx): Promise<CreateCampaignResult> => {
    const existingSnap = await tx.get(campaignRef(db, campaignId));
    if (existingSnap.exists) {
      const existing = existingSnap.data()!;
      return { campaignId, version: existing.version as number, created: false };
    }
    await requireActiveOrganizationInTransaction(tx, db, organizationId);
    await requireEligibleTargetsInTransaction(tx, db, organizationId, rule, eligibleProductIds, eligibleCategoryIds);

    const now = Timestamp.now();
    const version = 1;
    const live: CampaignDefinition = {
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
      active: true,
      archived: false,
      sortOrder,
      version,
      createdAt: now,
      updatedAt: now,
    };
    const versionSnapshot: CampaignVersionRecord = {
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
      version,
      effectiveAt: now,
      createdAt: now,
    };
    tx.set(campaignRef(db, campaignId), live);
    tx.create(campaignVersionRef(db, campaignId, version), versionSnapshot);
    return { campaignId, version, created: true };
  });
}

export interface UpdateCampaignOverrides {
  title?: unknown;
  description?: unknown;
  campaignType?: unknown;
  rule?: unknown;
  eligibleChannels?: unknown;
  eligibleProductIds?: unknown;
  eligibleCategoryIds?: unknown;
  minimumBasketMinorUnits?: unknown;
  schedule?: unknown;
  usageLimit?: unknown;
  perCustomerUsageLimit?: unknown;
  sortOrder?: unknown;
}

export interface UpdateCampaignResult {
  campaignId: string;
  version: number;
}

/**
 * Creates the NEXT immutable version — never mutates a prior version doc.
 * Any field omitted from `overrides` carries over unchanged from the
 * current live definition. `active`/`archived` are never touched here —
 * they have their own dedicated, non-versioning operations below, mirroring
 * `updateLoyaltyRewardByCreatingNextVersion`'s exact discipline.
 */
export async function updateCampaignByCreatingNextVersion(
  db: Firestore,
  organizationId: string,
  campaignId: string,
  overrides: UpdateCampaignOverrides,
): Promise<UpdateCampaignResult> {
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    throw new HttpsError("invalid-argument", "organizationId is required.");
  }
  const sanitizedId = sanitizeCampaignId(campaignId);

  return db.runTransaction(async (tx): Promise<UpdateCampaignResult> => {
    const snap = await tx.get(campaignRef(db, sanitizedId));
    if (!snap.exists) {
      throw new HttpsError("not-found", `Campaign "${sanitizedId}" does not exist.`);
    }
    const current = snap.data() as CampaignDefinition;
    if (current.organizationId !== organizationId) {
      throw new HttpsError(
        "failed-precondition",
        `Campaign "${sanitizedId}" does not belong to organization "${organizationId}".`,
      );
    }

    const title = overrides.title !== undefined ? sanitizeCampaignTitle(overrides.title) : current.title;
    const description =
      overrides.description !== undefined ? sanitizeCampaignDescription(overrides.description) : current.description;
    const campaignType =
      overrides.campaignType !== undefined ? sanitizeCampaignType(overrides.campaignType) : current.campaignType;
    const rule = overrides.rule !== undefined ? sanitizeCampaignRule(overrides.rule) : current.rule;
    validateCampaignTypeRuleConsistency(campaignType, rule);
    const eligibleChannels =
      overrides.eligibleChannels !== undefined
        ? sanitizeCampaignEligibleChannels(overrides.eligibleChannels)
        : current.eligibleChannels;
    const eligibleProductIds =
      overrides.eligibleProductIds !== undefined
        ? sanitizeOptionalEligibleProductIds(overrides.eligibleProductIds)
        : current.eligibleProductIds;
    const eligibleCategoryIds =
      overrides.eligibleCategoryIds !== undefined
        ? sanitizeOptionalEligibleCategoryIds(overrides.eligibleCategoryIds)
        : current.eligibleCategoryIds;
    const minimumBasketMinorUnits =
      overrides.minimumBasketMinorUnits !== undefined
        ? sanitizeOptionalMinimumBasketMinorUnits(overrides.minimumBasketMinorUnits)
        : current.minimumBasketMinorUnits;
    const schedule: CampaignSchedule =
      overrides.schedule !== undefined ? sanitizeCampaignSchedule(overrides.schedule) : current.schedule;
    const usageLimit =
      overrides.usageLimit !== undefined
        ? sanitizeOptionalUsageLimit(overrides.usageLimit, "usageLimit")
        : current.usageLimit;
    const perCustomerUsageLimit =
      overrides.perCustomerUsageLimit !== undefined
        ? sanitizeOptionalUsageLimit(overrides.perCustomerUsageLimit, "perCustomerUsageLimit")
        : current.perCustomerUsageLimit;
    const sortOrder =
      overrides.sortOrder !== undefined ? sanitizeSortOrder(overrides.sortOrder) : current.sortOrder;

    await requireActiveOrganizationInTransaction(tx, db, organizationId);
    await requireEligibleTargetsInTransaction(tx, db, organizationId, rule, eligibleProductIds, eligibleCategoryIds);

    const now = Timestamp.now();
    const version = current.version + 1;
    const live: CampaignDefinition = {
      ...current,
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
      sortOrder,
      version,
      updatedAt: now,
    };
    const versionSnapshot: CampaignVersionRecord = {
      campaignId: sanitizedId,
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
      version,
      effectiveAt: now,
      createdAt: now,
    };
    tx.set(campaignRef(db, sanitizedId), live);
    tx.create(campaignVersionRef(db, sanitizedId, version), versionSnapshot);
    return { campaignId: sanitizedId, version };
  });
}

/**
 * Flips `active` on the LIVE doc only — never creates a new version. An
 * archived campaign cannot be reactivated through this operation — see
 * [archiveCampaign] below; mirrors `setLoyaltyRewardActive`'s exact
 * discipline, including "un-archiving is not a supported operation."
 */
export async function setCampaignActive(
  db: Firestore,
  organizationId: string,
  campaignId: string,
  active: boolean,
): Promise<void> {
  const sanitizedId = sanitizeCampaignId(campaignId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(campaignRef(db, sanitizedId));
    if (!snap.exists) {
      throw new HttpsError("not-found", `Campaign "${sanitizedId}" does not exist.`);
    }
    const current = snap.data() as CampaignDefinition;
    if (current.organizationId !== organizationId) {
      throw new HttpsError(
        "failed-precondition",
        `Campaign "${sanitizedId}" does not belong to organization "${organizationId}".`,
      );
    }
    if (current.archived) {
      throw new HttpsError("failed-precondition", `Campaign "${sanitizedId}" is archived and cannot be reactivated.`);
    }
    tx.update(campaignRef(db, sanitizedId), { active, updatedAt: Timestamp.now() });
  });
}

/**
 * The one, permanent, non-destructive "delete" (locked requirement: "no
 * destructive campaign delete; archive only"). Forces `active: false`
 * alongside `archived: true`. Every version and the live doc itself remain
 * permanently stored; nothing is ever removed from Firestore.
 */
export async function archiveCampaign(db: Firestore, organizationId: string, campaignId: string): Promise<void> {
  const sanitizedId = sanitizeCampaignId(campaignId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(campaignRef(db, sanitizedId));
    if (!snap.exists) {
      throw new HttpsError("not-found", `Campaign "${sanitizedId}" does not exist.`);
    }
    const current = snap.data() as CampaignDefinition;
    if (current.organizationId !== organizationId) {
      throw new HttpsError(
        "failed-precondition",
        `Campaign "${sanitizedId}" does not belong to organization "${organizationId}".`,
      );
    }
    tx.update(campaignRef(db, sanitizedId), { active: false, archived: true, updatedAt: Timestamp.now() });
  });
}

export interface DuplicateCampaignResult {
  campaignId: string;
  version: number;
}

/**
 * Copies a source campaign's full rule-defining definition into a brand
 * new campaign id, as version 1, deliberately created **`active: false`**
 * (never auto-activated — a duplicate is a starting point for editing, not
 * an instruction to immediately run two identical live promotions). Never
 * copies `usageLimit`'s CURRENT usage — a new campaign id starts with no
 * `campaignUsageCounters` document at all (usage is scoped by campaignId,
 * so this is automatic, not something this function needs to reset).
 */
export async function duplicateCampaign(
  db: Firestore,
  organizationId: string,
  sourceCampaignId: string,
  newCampaignId: string,
): Promise<DuplicateCampaignResult> {
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    throw new HttpsError("invalid-argument", "organizationId is required.");
  }
  const sanitizedSourceId = sanitizeCampaignId(sourceCampaignId);
  const sanitizedNewId = sanitizeCampaignId(newCampaignId);
  if (sanitizedSourceId === sanitizedNewId) {
    throw new HttpsError("invalid-argument", "newCampaignId must differ from sourceCampaignId.");
  }

  return db.runTransaction(async (tx): Promise<DuplicateCampaignResult> => {
    const sourceSnap = await tx.get(campaignRef(db, sanitizedSourceId));
    if (!sourceSnap.exists) {
      throw new HttpsError("not-found", `Campaign "${sanitizedSourceId}" does not exist.`);
    }
    const source = sourceSnap.data() as CampaignDefinition;
    if (source.organizationId !== organizationId) {
      throw new HttpsError(
        "failed-precondition",
        `Campaign "${sanitizedSourceId}" does not belong to organization "${organizationId}".`,
      );
    }
    const newSnap = await tx.get(campaignRef(db, sanitizedNewId));
    if (newSnap.exists) {
      throw new HttpsError("already-exists", `Campaign "${sanitizedNewId}" already exists.`);
    }

    const now = Timestamp.now();
    const version = 1;
    const live: CampaignDefinition = {
      campaignId: sanitizedNewId,
      organizationId,
      title: source.title,
      description: source.description,
      campaignType: source.campaignType,
      rule: source.rule,
      eligibleChannels: source.eligibleChannels,
      eligibleProductIds: source.eligibleProductIds,
      eligibleCategoryIds: source.eligibleCategoryIds,
      minimumBasketMinorUnits: source.minimumBasketMinorUnits,
      schedule: source.schedule,
      usageLimit: source.usageLimit,
      perCustomerUsageLimit: source.perCustomerUsageLimit,
      active: false,
      archived: false,
      sortOrder: source.sortOrder,
      version,
      createdAt: now,
      updatedAt: now,
    };
    const versionSnapshot: CampaignVersionRecord = {
      campaignId: sanitizedNewId,
      organizationId,
      title: live.title,
      description: live.description,
      campaignType: live.campaignType,
      rule: live.rule,
      eligibleChannels: live.eligibleChannels,
      eligibleProductIds: live.eligibleProductIds,
      eligibleCategoryIds: live.eligibleCategoryIds,
      minimumBasketMinorUnits: live.minimumBasketMinorUnits,
      schedule: live.schedule,
      usageLimit: live.usageLimit,
      perCustomerUsageLimit: live.perCustomerUsageLimit,
      version,
      effectiveAt: now,
      createdAt: now,
    };
    tx.set(campaignRef(db, sanitizedNewId), live);
    tx.create(campaignVersionRef(db, sanitizedNewId, version), versionSnapshot);
    return { campaignId: sanitizedNewId, version };
  });
}
