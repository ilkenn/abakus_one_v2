import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, Transaction } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { sha256Hex } from "./submitTakeawayOrder";

/**
 * `requestCustomerPhotoUploadGrant` — Profile P.4.2A (2026-08-19).
 *
 * Closes the exact gap `docs/decisions.md` P.4.1 disclosed and deliberately
 * did not fix: `storage.rules`' `customerPhotos/{organizationId}/{uid}/...`
 * path validated the uploading `uid` against the caller but never verified
 * the caller actually belongs to `organizationId` — an authenticated
 * customer of org A could write under org B's path segment. The fix
 * chosen (per the locked architecture decision) is a server-issued,
 * short-lived upload grant: the client still uploads bytes directly to
 * Cloud Storage (never proxied through this Function), but only to one
 * exact path this Function has already authorized, and `storage.rules`
 * verifies that authorization by reading the grant back from Firestore
 * (`firestore.get(...)`, a genuine cross-service Storage-Rules capability)
 * before allowing the write.
 *
 * **Never trusts a client-supplied `organizationId` as authorization
 * truth** — tenant membership is independently verified server-side via
 * `tenantCustomers/{organizationId}_{uid}`'s existence, the same composite-
 * key record `firestore.rules`' own `isTenantCustomer()` helper already
 * uses (P.4.1). This is, on purpose, the first Cloud Function to actually
 * query that collection (previously documented-but-unused from `functions/
 * src`, per the P.4.1 audit).
 *
 * **Quota accounting includes outstanding grants, not just existing
 * `CustomerPhoto` records** — "a user must NOT be able to request 10
 * parallel grants while already having 10 eligible photos" (locked
 * requirement). See [countReservedOrEligibleSlots].
 *
 * **Idempotent, mirroring `submitDeliveryOrder`/`submitTakeawayOrder`'s
 * exact shape** (`sha256Hex`, deterministic id from `(uid, requestKey)`,
 * fingerprint-on-replay comparison) rather than inventing a new pattern.
 * An optional client-supplied `requestKey` derives BOTH the grant's
 * Firestore document id and its Storage object name — a retried request
 * with the same key targets the exact same reservation and the exact same
 * (still-unwritten, or already-written-and-thus-harmlessly-re-returned)
 * Storage path, instead of minting a fresh grant/quota reservation on every
 * network retry. No `requestKey` -> always a fresh, non-idempotent grant.
 */

// Mirrors `CustomerPhoto.maxEligiblePhotos`
// (`lib/features/admin/domain/customer/customer_photo.dart`) — kept in sync
// by hand across the Dart/TypeScript boundary, same disclosed limitation
// `CustomerPhotoLimitReachedViolation`'s own doc comment already accepts
// for the equivalent client-side constant (`core -> feature` imports don't
// apply here, but there is still no single source of truth reachable from
// both languages).
const MAX_ELIGIBLE_PHOTOS = 10;

// Short enough that an abandoned upload frees its reservation quickly;
// long enough for a real (if slow) mobile upload to complete. Not tied to
// any product requirement beyond "grant must expire" — a reasonable,
// documented default, easy to tune later without changing the model.
const GRANT_TTL_MS = 15 * 60 * 1000; // 15 minutes

const CUSTOMER_PHOTOS_COLLECTION = "customerPhotos";
const UPLOAD_GRANTS_COLLECTION = "customerPhotoUploadGrants";
const TENANT_CUSTOMERS_COLLECTION = "tenantCustomers";

// Statuses counted as "still consuming an eligible-photo slot" — mirrors
// `CustomerPhoto.countsTowardEligibleLimit`
// (pendingReview/underReview/approved count; rejected/removed never do).
const ELIGIBLE_PHOTO_STATUSES = ["pendingReview", "underReview", "approved"];

interface RequestUploadGrantResult {
  grantId: string;
  objectPath: string;
  expiresAtMillis: number;
  contentType: string;
  reused: boolean;
}

function db() {
  return getFirestore();
}

function objectPathFor(organizationId: string, uid: string, grantId: string): string {
  return `tenants/${organizationId}/customerPhotos/${uid}/${grantId}`;
}

/**
 * Counts every slot the customer currently occupies or has reserved:
 * existing `customerPhotos` in an eligible status, plus outstanding
 * `customerPhotoUploadGrants` that are still `issued` and not yet expired.
 * A stale grant whose `expiresAt` has passed but was never explicitly
 * marked `expired` is filtered out here rather than relying on a
 * background sweep — "grant expiry must eventually release reserved
 * capacity" holds the moment `now` passes `expiresAt`, not only once
 * something gets around to writing a status change.
 *
 * Read entirely inside the caller's transaction — every read in this
 * function happens before [tx]'s first write, preserving this codebase's
 * existing "reads before writes" transaction discipline
 * (`reservationHoldOps.ts`/`assignReservationTable.ts`).
 */
async function countReservedOrEligibleSlots(
  tx: Transaction,
  uid: string,
  now: Timestamp,
  excludeGrantId?: string,
): Promise<number> {
  const eligiblePhotosSnap = await tx.get(
    db()
      .collection(CUSTOMER_PHOTOS_COLLECTION)
      .where("customerId", "==", uid)
      .where("status", "in", ELIGIBLE_PHOTO_STATUSES),
  );
  const activeGrantsSnap = await tx.get(
    db().collection(UPLOAD_GRANTS_COLLECTION).where("uid", "==", uid).where("status", "==", "issued"),
  );
  const activeUnexpiredGrantCount = activeGrantsSnap.docs.filter((doc) => {
    if (doc.id === excludeGrantId) return false; // the grant we're about to reissue over, if any.
    const expiresAt = doc.data().expiresAt as Timestamp | undefined;
    return expiresAt != null && expiresAt.toMillis() > now.toMillis();
  }).length;

  return eligiblePhotosSnap.size + activeUnexpiredGrantCount;
}

export const requestCustomerPhotoUploadGrant = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<RequestUploadGrantResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Photo upload requires a real, phone-verified customer identity.",
      );
    }
    const uid = request.auth.uid;

    const organizationId = request.data?.organizationId;
    if (typeof organizationId !== "string" || organizationId.length === 0) {
      throw new HttpsError("invalid-argument", "organizationId is required.");
    }
    const contentType = request.data?.contentType;
    if (typeof contentType !== "string" || !contentType.startsWith("image/")) {
      throw new HttpsError("invalid-argument", "contentType must be an image MIME type.");
    }
    const requestKeyRaw = request.data?.requestKey;
    const requestKey = typeof requestKeyRaw === "string" && requestKeyRaw.length > 0 ? requestKeyRaw : null;

    // Never trust the client's organizationId as authorization truth —
    // independently verify real tenant membership via the existing
    // tenantCustomers/{organizationId}_{uid} composite-key record (the
    // same mechanism firestore.rules' own isTenantCustomer() helper uses).
    const tenantCustomerDoc = await db()
      .collection(TENANT_CUSTOMERS_COLLECTION)
      .doc(`${organizationId}_${uid}`)
      .get();
    if (!tenantCustomerDoc.exists) {
      throw new HttpsError("permission-denied", "You are not a customer of this organization.");
    }

    // A requestKey derives a deterministic grant id, matching
    // submitDeliveryOrder/submitTakeawayOrder's exact idempotency shape —
    // the same (uid, requestKey) pair always maps to the same document
    // AND the same Storage object path, so a client retry never mints a
    // second reservation for the same logical upload attempt.
    const grantId = requestKey
      ? sha256Hex(`${uid}|${requestKey}`).slice(0, 32)
      : sha256Hex(`${uid}|${Date.now()}|${Math.random()}`).slice(0, 32);
    const objectPath = objectPathFor(organizationId, uid, grantId);

    const result = await db().runTransaction(async (tx): Promise<RequestUploadGrantResult> => {
      const grantRef = db().collection(UPLOAD_GRANTS_COLLECTION).doc(grantId);
      const now = Timestamp.now();

      // Reads first, always — this grant read, then (only if needed) the
      // quota reads below, all before any tx.set().
      const existingGrantSnap = await tx.get(grantRef);
      if (existingGrantSnap.exists) {
        const existing = existingGrantSnap.data()!;
        const stillActive = existing.status === "issued" && (existing.expiresAt as Timestamp).toMillis() > now.toMillis();
        if (stillActive) {
          if (existing.organizationId !== organizationId || existing.contentType !== contentType) {
            throw new HttpsError(
              "failed-precondition",
              "requestKey was already used to request an upload grant with different parameters.",
            );
          }
          // Idempotent replay: same request, same still-valid grant — no
          // new reservation is consumed, nothing is re-written.
          return {
            grantId,
            objectPath: existing.objectPath,
            expiresAtMillis: (existing.expiresAt as Timestamp).toMillis(),
            contentType: existing.contentType,
            reused: true,
          };
        }
        // Expired (or, defensively, a non-"issued" status) — falls through
        // to reissue a fresh grant over the same deterministic id below,
        // which also naturally reuses the same Storage object path.
      }

      const reservedOrEligibleCount = await countReservedOrEligibleSlots(tx, uid, now, grantId);
      if (reservedOrEligibleCount >= MAX_ELIGIBLE_PHOTOS) {
        throw new HttpsError(
          "resource-exhausted",
          `Customer already has ${MAX_ELIGIBLE_PHOTOS} eligible photos or outstanding upload reservations.`,
        );
      }

      const expiresAt = Timestamp.fromMillis(now.toMillis() + GRANT_TTL_MS);
      tx.set(grantRef, {
        uid,
        organizationId,
        objectPath,
        contentType,
        status: "issued",
        createdAt: now,
        expiresAt,
      });

      return {
        grantId,
        objectPath,
        expiresAtMillis: expiresAt.toMillis(),
        contentType,
        reused: false,
      };
    });

    logger.info("[requestCustomerPhotoUploadGrant] grant issued", {
      uid,
      organizationId,
      grantId: result.grantId,
      reused: result.reused,
    });

    return result;
  },
);

export { MAX_ELIGIBLE_PHOTOS, GRANT_TTL_MS, ELIGIBLE_PHOTO_STATUSES };
