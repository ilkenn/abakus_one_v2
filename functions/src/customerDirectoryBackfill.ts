import { onCall } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import type { Firestore } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requirePlatformCapability } from "./platformCapabilities";
import { CUSTOMERS_COLLECTION, TENANT_CUSTOMERS_COLLECTION, isProfileComplete } from "./completeCustomerProfile";
import {
  PLATFORM_CUSTOMER_DIRECTORY_COLLECTION,
  CUSTOMER_DIRECTORY_ENTRIES_COLLECTION,
  normalizeDisplayName,
  normalizePhoneForSearch,
  computePhoneSearchHash,
} from "./customerDirectoryConfig";

/**
 * AP-3 continuation — Customer Directory backfill tooling.
 *
 * Both projections are ALREADY populated for every customer going forward
 * by `completeCustomerProfile`'s live transactional write (Wave 3) — this
 * module exists only to create the projection for a customer who completed
 * registration BEFORE that write existed. A document that already exists at
 * the target id is always left untouched (counted as skipped, never
 * re-merged) — this is what makes a rerun after a partial/interrupted run,
 * or a second identical run, produce byte-identical results to the first
 * successful run: every source id is either "already has a projection"
 * (skip, forever) or "gets exactly one projection created, exactly once"
 * (create), with no third state, so no run can ever produce a duplicate.
 *
 * Deliberately bounded/cursor-based rather than a single unbounded pass —
 * mirrors this codebase's own pagination convention (`listTenantCustomers`
 * et al.'s `cursor`/`nextCursor` shape) applied to a write workload instead
 * of a read one. The caller (an operator script or the platformOwner-gated
 * callable wrapper below) loops, passing the previous batch's `nextCursor`
 * back in as the next call's `cursor`, until `nextCursor` comes back `null`.
 *
 * Never executed against production in this phase — no production Firebase
 * project has this deployed; these callables exist and are tested against
 * the emulator only.
 */

const DEFAULT_BATCH_SIZE = 200;
const MAX_BATCH_SIZE = 500; // Firestore batch-write cap.

export interface BackfillBatchOptions {
  batchSize?: number;
  cursor?: string | null;
  dryRun?: boolean;
}

export interface BackfillBatchResult {
  scannedCount: number;
  createdCount: number;
  skippedCount: number;
  nextCursor: string | null;
  dryRun: boolean;
}

function clampBatchSize(raw: number | undefined): number {
  if (typeof raw !== "number" || !Number.isFinite(raw) || raw <= 0) return DEFAULT_BATCH_SIZE;
  return Math.min(Math.floor(raw), MAX_BATCH_SIZE);
}

/**
 * One bounded batch of the platform-projection backfill. Source of truth is
 * `customers/{uid}`, gated through the SAME `isProfileComplete` check
 * `completeCustomerProfile` itself uses — a backfilled entry is held to the
 * identical completeness bar as a live one, never a looser one.
 */
export async function backfillPlatformCustomerDirectoryBatch(
  db: Firestore,
  options: BackfillBatchOptions = {},
): Promise<BackfillBatchResult> {
  const batchSize = clampBatchSize(options.batchSize);
  const dryRun = options.dryRun === true;

  let query = db.collection(CUSTOMERS_COLLECTION).orderBy("__name__").limit(batchSize);
  if (options.cursor) {
    const cursorSnap = await db.collection(CUSTOMERS_COLLECTION).doc(options.cursor).get();
    if (cursorSnap.exists) query = query.startAfter(cursorSnap);
  }
  const pageSnap = await query.get();

  const candidates = pageSnap.docs.filter((doc) => {
    const data = doc.data();
    return isProfileComplete(data) && typeof data.displayName === "string" && typeof data.phoneNumber === "string";
  });
  const skippedIncomplete = pageSnap.docs.length - candidates.length;

  const targetRefs = candidates.map((doc) => db.collection(PLATFORM_CUSTOMER_DIRECTORY_COLLECTION).doc(doc.id));
  const existingTargets = targetRefs.length > 0 ? await db.getAll(...targetRefs) : [];

  let createdCount = 0;
  let skippedExisting = 0;
  const writeBatch = db.batch();
  const now = Timestamp.now();

  candidates.forEach((doc, i) => {
    if (existingTargets[i].exists) {
      skippedExisting++;
      return;
    }
    const data = doc.data();
    const uid = doc.id;
    const displayName = data.displayName as string;
    const phoneNumber = data.phoneNumber as string;
    createdCount++;
    if (!dryRun) {
      writeBatch.set(targetRefs[i], {
        uid,
        displayName,
        displayNameNormalized: normalizeDisplayName(displayName),
        phoneNumber,
        phoneSearchHash: computePhoneSearchHash(normalizePhoneForSearch(phoneNumber)),
        registrationDate: data.createdAt instanceof Timestamp ? data.createdAt : now,
        accountState: "active",
        updatedAt: now,
        version: 1,
      });
    }
  });
  if (!dryRun && createdCount > 0) await writeBatch.commit();

  const isLastPage = pageSnap.docs.length < batchSize;
  return {
    scannedCount: pageSnap.docs.length,
    createdCount,
    skippedCount: skippedIncomplete + skippedExisting,
    nextCursor: isLastPage ? null : pageSnap.docs[pageSnap.docs.length - 1].id,
    dryRun,
  };
}

/**
 * One bounded batch of the tenant-projection backfill. Source of truth is
 * `tenantCustomers/{organizationId}_{uid}` — the SAME canonical membership
 * collection `completeCustomerProfile`'s own tenant-projection write reads
 * from — never inventing a tenant relationship from any other signal (e.g.
 * an order's `organizationId`). Each source document already carries its
 * own `organizationId`, so cross-tenant isolation is structural: the target
 * id is always derived from that SAME document's own field, never a
 * caller-supplied one.
 */
export async function backfillTenantCustomerDirectoryBatch(
  db: Firestore,
  options: BackfillBatchOptions = {},
): Promise<BackfillBatchResult> {
  const batchSize = clampBatchSize(options.batchSize);
  const dryRun = options.dryRun === true;

  let query = db.collection(TENANT_CUSTOMERS_COLLECTION).orderBy("__name__").limit(batchSize);
  if (options.cursor) {
    const cursorSnap = await db.collection(TENANT_CUSTOMERS_COLLECTION).doc(options.cursor).get();
    if (cursorSnap.exists) query = query.startAfter(cursorSnap);
  }
  const pageSnap = await query.get();

  const memberships = pageSnap.docs
    .map((doc) => ({ doc, data: doc.data() }))
    .filter(
      (m) => typeof m.data.organizationId === "string" && typeof m.data.uid === "string",
    );
  let skippedCount = pageSnap.docs.length - memberships.length;

  const targetRefs = memberships.map((m) =>
    db.collection(CUSTOMER_DIRECTORY_ENTRIES_COLLECTION).doc(`${m.data.organizationId as string}_${m.data.uid as string}`),
  );
  const customerRefs = memberships.map((m) => db.collection(CUSTOMERS_COLLECTION).doc(m.data.uid as string));
  const [existingTargets, customerSnaps] = targetRefs.length > 0
    ? await Promise.all([db.getAll(...targetRefs), db.getAll(...customerRefs)])
    : [[], []];

  let createdCount = 0;
  const writeBatch = db.batch();
  const now = Timestamp.now();

  memberships.forEach((m, i) => {
    if (existingTargets[i].exists) {
      skippedCount++;
      return;
    }
    const customerData = customerSnaps[i].data();
    if (!customerSnaps[i].exists || !isProfileComplete(customerData) || typeof customerData?.displayName !== "string" || typeof customerData?.phoneNumber !== "string") {
      skippedCount++;
      return;
    }
    const organizationId = m.data.organizationId as string;
    const uid = m.data.uid as string;
    const displayName = customerData.displayName as string;
    const phoneNumber = customerData.phoneNumber as string;
    createdCount++;
    if (!dryRun) {
      writeBatch.set(targetRefs[i], {
        organizationId,
        customerId: uid,
        displayName,
        displayNameNormalized: normalizeDisplayName(displayName),
        phoneNumber,
        phoneSearchHash: computePhoneSearchHash(normalizePhoneForSearch(phoneNumber)),
        registrationDate: m.data.createdAt instanceof Timestamp ? m.data.createdAt : now,
        lastActivityAt: now,
        accountState: "active",
        relatedBranchIds: [],
        lastOrderAt: null,
        totalOrderCount: 0,
        updatedAt: now,
        version: 1,
      });
    }
  });
  if (!dryRun && createdCount > 0) await writeBatch.commit();

  const isLastPage = pageSnap.docs.length < batchSize;
  return {
    scannedCount: pageSnap.docs.length,
    createdCount,
    skippedCount,
    nextCursor: isLastPage ? null : pageSnap.docs[pageSnap.docs.length - 1].id,
    dryRun,
  };
}

function readBatchOptions(request: CallableRequest): BackfillBatchOptions {
  const data = (request.data ?? {}) as Record<string, unknown>;
  return {
    cursor: typeof data.cursor === "string" && data.cursor.length > 0 ? data.cursor : null,
    batchSize: typeof data.batchSize === "number" ? data.batchSize : undefined,
    dryRun: data.dryRun === true,
  };
}

export const runPlatformCustomerDirectoryBackfill = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest): Promise<BackfillBatchResult> => {
    requirePlatformCapability(request, "customerDirectory.runBackfill");
    return backfillPlatformCustomerDirectoryBatch(getFirestore(), readBatchOptions(request));
  },
);

export const runTenantCustomerDirectoryBackfill = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest): Promise<BackfillBatchResult> => {
    requirePlatformCapability(request, "customerDirectory.runBackfill");
    return backfillTenantCustomerDirectoryBatch(getFirestore(), readBatchOptions(request));
  },
);
