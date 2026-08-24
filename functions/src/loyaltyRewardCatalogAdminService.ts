import { Timestamp, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { loadCanonicalMenuProduct } from "./takeawayCatalog";
import {
  LOYALTY_REWARD_CATALOG_COLLECTION,
  LOYALTY_REWARD_CATALOG_VERSIONS_COLLECTION,
  loyaltyRewardCatalogVersionDocId,
  sanitizeRewardId,
  sanitizeRewardTitle,
  sanitizeRewardDescription,
  sanitizeRewardType,
  sanitizeEligibleProductIds,
  sanitizeEligibleChannels,
  sanitizeBoncukCost,
  sanitizeSortOrder,
  sanitizeOptionalTimestamp,
  validateValidityWindow,
  type LoyaltyRewardCatalogEntry,
  type LoyaltyRewardCatalogVersionSnapshot,
  type LoyaltyRewardType,
} from "./loyaltyRewardCatalog";

/**
 * `loyaltyRewardCatalogAdminService` — Boncuk Loyalty Program P7-B
 * (2026-08-24).
 *
 * Trusted service/domain operations for managing the Reward Catalog —
 * **not Cloud Function callables**. Per this phase's explicit instruction
 * ("do NOT implement Admin UI," "if an Admin callable would create
 * premature permission/UI scope, keep management as trusted backend
 * service primitives plus dev bootstrap/seed for now"): every operation
 * here is a plain, directly-importable async function, callable today only
 * from the local dev-seed script (`functions/scripts/seed_dev_loyalty_reward
 * _catalog.mjs`, via the compiled `lib/` output — mirrors
 * `migrate_canonical_catalog.mjs`'s own `createRequire` reuse of
 * `catalogMigration.js` exactly) and, in a future phase, from a real
 * Admin-authorized `onCall` wrapper that does nothing more than
 * authenticate/authorize the caller and forward validated input here — no
 * redesign needed when that phase arrives.
 *
 * **Challenged against existing conventions before choosing this shape**:
 * `provisionOrganization`/`provisionRestaurant`/`provisionBranch` ARE real
 * `onCall` callables, but they're authorized via `platformOwner`, a role
 * that already exists and is exercised today by `seed_dev_tenant.mjs`. No
 * equivalent "reward catalog manager" role/permission exists yet, and
 * inventing one now — before any real Admin screen consumes it — would be
 * exactly the "premature permission/UI scope" this phase's own instruction
 * warns against. Plain trusted functions, invoked only via Admin
 * SDK-privileged contexts (a dev script today, a real authorized callable
 * later), avoid that without blocking the later addition.
 *
 * **Every operation manages its own transaction** (never accepts a
 * caller-supplied `tx`) — these are top-level trusted operations, not
 * composed into a larger transaction the way `loyaltyPolicy.ts`'s
 * transaction-scoped read/write pair is. Mirrors `provisionRestaurant.ts`'s
 * own "reads first inside `db.runTransaction`, HttpsError on failure" shape
 * exactly.
 */

function organizationRef(db: Firestore, organizationId: string) {
  return db.collection("organizations").doc(organizationId);
}

function rewardRef(db: Firestore, rewardId: string) {
  return db.collection(LOYALTY_REWARD_CATALOG_COLLECTION).doc(rewardId);
}

function rewardVersionRef(db: Firestore, rewardId: string, version: number) {
  return db
    .collection(LOYALTY_REWARD_CATALOG_VERSIONS_COLLECTION)
    .doc(loyaltyRewardCatalogVersionDocId(rewardId, version));
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
 * Validates every id in `productIds` exists in the real canonical
 * `menuProducts` collection and belongs to `organizationId` — never
 * accepts a client/caller-asserted title, price, or category as proof of
 * eligibility; the only trust anchor is the canonical product document
 * itself. All reads happen inside the transaction (before any write),
 * mirroring `reservationPreorder.ts`'s own "every catalog read takes the
 * surrounding transaction" discipline.
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

export interface CreateLoyaltyRewardInput {
  organizationId: string;
  rewardId: string;
  title: string;
  description: string;
  rewardType: LoyaltyRewardType;
  eligibleProductIds: string[];
  eligibleChannels: string[];
  boncukCost: number;
  sortOrder: number;
  validFrom?: unknown;
  validUntil?: unknown;
}

export interface CreateLoyaltyRewardResult {
  rewardId: string;
  version: number;
  created: boolean;
}

/**
 * Idempotent by design: if `rewardId` already exists (regardless of its
 * current field values), this is a safe no-op that returns the existing
 * live version untouched — `created: false`. This is the exact property
 * the local dev-seed script's own "rerunning must not create duplicates"
 * requirement relies on. It is deliberately NOT "upsert" (never rewrites
 * an existing reward's fields) — a genuine field change must go through
 * [updateLoyaltyRewardByCreatingNextVersion] instead, so "did this reward
 * change" is always answered by "is there a new version," never by a
 * silent overwrite of version 1.
 */
export async function createLoyaltyReward(
  db: Firestore,
  input: CreateLoyaltyRewardInput,
): Promise<CreateLoyaltyRewardResult> {
  const organizationId = input.organizationId;
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    throw new HttpsError("invalid-argument", "organizationId is required.");
  }
  const rewardId = sanitizeRewardId(input.rewardId);
  const title = sanitizeRewardTitle(input.title);
  const description = sanitizeRewardDescription(input.description);
  const rewardType = sanitizeRewardType(input.rewardType);
  const eligibleProductIds = sanitizeEligibleProductIds(input.eligibleProductIds);
  const eligibleChannels = sanitizeEligibleChannels(input.eligibleChannels);
  const boncukCost = sanitizeBoncukCost(input.boncukCost);
  const sortOrder = sanitizeSortOrder(input.sortOrder);
  const validFrom = sanitizeOptionalTimestamp(input.validFrom, "validFrom");
  const validUntil = sanitizeOptionalTimestamp(input.validUntil, "validUntil");
  validateValidityWindow(validFrom, validUntil);

  return db.runTransaction(async (tx): Promise<CreateLoyaltyRewardResult> => {
    // Reads first, always.
    const existingSnap = await tx.get(rewardRef(db, rewardId));
    if (existingSnap.exists) {
      const existing = existingSnap.data()!;
      return { rewardId, version: existing.version as number, created: false };
    }
    await requireActiveOrganizationInTransaction(tx, db, organizationId);
    await requireEligibleCanonicalProductsInTransaction(tx, db, organizationId, eligibleProductIds);

    const now = Timestamp.now();
    const version = 1;
    const live: LoyaltyRewardCatalogEntry = {
      rewardId,
      organizationId,
      title,
      description,
      rewardType,
      eligibleProductIds,
      eligibleChannels,
      boncukCost,
      active: true,
      archived: false,
      sortOrder,
      version,
      validFrom,
      validUntil,
      createdAt: now,
      updatedAt: now,
    };
    const versionSnapshot: LoyaltyRewardCatalogVersionSnapshot = {
      rewardId,
      organizationId,
      title,
      description,
      rewardType,
      eligibleProductIds,
      eligibleChannels,
      boncukCost,
      sortOrder,
      version,
      validFrom,
      validUntil,
      effectiveAt: now,
      createdAt: now,
    };
    tx.set(rewardRef(db, rewardId), live);
    tx.create(rewardVersionRef(db, rewardId, version), versionSnapshot);
    return { rewardId, version, created: true };
  });
}

export interface UpdateLoyaltyRewardOverrides {
  title?: unknown;
  description?: unknown;
  eligibleProductIds?: unknown;
  eligibleChannels?: unknown;
  boncukCost?: unknown;
  sortOrder?: unknown;
  validFrom?: unknown;
  validUntil?: unknown;
}

export interface UpdateLoyaltyRewardResult {
  rewardId: string;
  version: number;
}

/**
 * Creates the NEXT immutable version — never mutates a prior version doc.
 * Any field omitted from `overrides` carries over unchanged from the
 * current live definition (a partial edit, not a full re-specification).
 * `rewardType`/`active`/`archived` are never touched here — `rewardType`
 * is fixed for a reward's lifetime this phase (MVP has only one value
 * anyway), and `active`/`archived` are operational flags with their own
 * dedicated, non-versioning operations below.
 */
export async function updateLoyaltyRewardByCreatingNextVersion(
  db: Firestore,
  organizationId: string,
  rewardId: string,
  overrides: UpdateLoyaltyRewardOverrides,
): Promise<UpdateLoyaltyRewardResult> {
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    throw new HttpsError("invalid-argument", "organizationId is required.");
  }
  const sanitizedId = sanitizeRewardId(rewardId);

  return db.runTransaction(async (tx): Promise<UpdateLoyaltyRewardResult> => {
    const snap = await tx.get(rewardRef(db, sanitizedId));
    if (!snap.exists) {
      throw new HttpsError("not-found", `Reward "${sanitizedId}" does not exist.`);
    }
    const current = snap.data() as LoyaltyRewardCatalogEntry;
    if (current.organizationId !== organizationId) {
      throw new HttpsError(
        "failed-precondition",
        `Reward "${sanitizedId}" does not belong to organization "${organizationId}".`,
      );
    }

    const title =
      overrides.title !== undefined ? sanitizeRewardTitle(overrides.title) : current.title;
    const description =
      overrides.description !== undefined
        ? sanitizeRewardDescription(overrides.description)
        : current.description;
    const eligibleProductIds =
      overrides.eligibleProductIds !== undefined
        ? sanitizeEligibleProductIds(overrides.eligibleProductIds)
        : current.eligibleProductIds;
    const eligibleChannels =
      overrides.eligibleChannels !== undefined
        ? sanitizeEligibleChannels(overrides.eligibleChannels)
        : current.eligibleChannels;
    const boncukCost =
      overrides.boncukCost !== undefined ? sanitizeBoncukCost(overrides.boncukCost) : current.boncukCost;
    const sortOrder =
      overrides.sortOrder !== undefined ? sanitizeSortOrder(overrides.sortOrder) : current.sortOrder;
    const validFrom =
      overrides.validFrom !== undefined
        ? sanitizeOptionalTimestamp(overrides.validFrom, "validFrom")
        : current.validFrom;
    const validUntil =
      overrides.validUntil !== undefined
        ? sanitizeOptionalTimestamp(overrides.validUntil, "validUntil")
        : current.validUntil;
    validateValidityWindow(validFrom, validUntil);

    await requireActiveOrganizationInTransaction(tx, db, organizationId);
    await requireEligibleCanonicalProductsInTransaction(tx, db, organizationId, eligibleProductIds);

    const now = Timestamp.now();
    const version = current.version + 1;
    const live: LoyaltyRewardCatalogEntry = {
      ...current,
      title,
      description,
      eligibleProductIds,
      eligibleChannels,
      boncukCost,
      sortOrder,
      validFrom,
      validUntil,
      version,
      updatedAt: now,
    };
    const versionSnapshot: LoyaltyRewardCatalogVersionSnapshot = {
      rewardId: sanitizedId,
      organizationId,
      title,
      description,
      rewardType: current.rewardType,
      eligibleProductIds,
      eligibleChannels,
      boncukCost,
      sortOrder,
      version,
      validFrom,
      validUntil,
      effectiveAt: now,
      createdAt: now,
    };
    tx.set(rewardRef(db, sanitizedId), live);
    tx.create(rewardVersionRef(db, sanitizedId, version), versionSnapshot);
    return { rewardId: sanitizedId, version };
  });
}

/**
 * Flips `active` on the LIVE doc only — never creates a new version (see
 * `loyaltyRewardCatalog.ts`'s own doc comment for why `active`/`archived`
 * are excluded from the versioned definition). An archived reward cannot
 * be reactivated through this operation alone — see [archiveLoyaltyReward]
 * below; calling this with `active: true` on an archived reward is
 * rejected, since "un-archiving" is deliberately not a supported P7-B
 * operation (archiving is intended as terminal for this phase).
 */
export async function setLoyaltyRewardActive(
  db: Firestore,
  organizationId: string,
  rewardId: string,
  active: boolean,
): Promise<void> {
  const sanitizedId = sanitizeRewardId(rewardId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(rewardRef(db, sanitizedId));
    if (!snap.exists) {
      throw new HttpsError("not-found", `Reward "${sanitizedId}" does not exist.`);
    }
    const current = snap.data() as LoyaltyRewardCatalogEntry;
    if (current.organizationId !== organizationId) {
      throw new HttpsError(
        "failed-precondition",
        `Reward "${sanitizedId}" does not belong to organization "${organizationId}".`,
      );
    }
    if (current.archived) {
      throw new HttpsError(
        "failed-precondition",
        `Reward "${sanitizedId}" is archived and cannot be reactivated.`,
      );
    }
    tx.update(rewardRef(db, sanitizedId), { active, updatedAt: Timestamp.now() });
  });
}

/**
 * The one, permanent, non-destructive "delete." Forces `active: false`
 * alongside `archived: true` — an archived reward is never independently
 * "active," collapsing away a meaningless combination rather than allowing
 * it to exist. Every version and the live doc itself remain permanently
 * stored; nothing is ever removed from Firestore.
 */
export async function archiveLoyaltyReward(
  db: Firestore,
  organizationId: string,
  rewardId: string,
): Promise<void> {
  const sanitizedId = sanitizeRewardId(rewardId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(rewardRef(db, sanitizedId));
    if (!snap.exists) {
      throw new HttpsError("not-found", `Reward "${sanitizedId}" does not exist.`);
    }
    const current = snap.data() as LoyaltyRewardCatalogEntry;
    if (current.organizationId !== organizationId) {
      throw new HttpsError(
        "failed-precondition",
        `Reward "${sanitizedId}" does not belong to organization "${organizationId}".`,
      );
    }
    tx.update(rewardRef(db, sanitizedId), {
      active: false,
      archived: true,
      updatedAt: Timestamp.now(),
    });
  });
}
