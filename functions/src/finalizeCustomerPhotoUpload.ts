import { onObjectFinalized, StorageEvent } from "firebase-functions/v2/storage";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";

/**
 * `finalizeCustomerPhotoUpload` — Profile P.4.2B1 (2026-08-19).
 *
 * The other half of the upload-grant design P.4.2A built: a client uploads
 * directly to Storage against a server-authorized path
 * (`requestCustomerPhotoUploadGrant`, `customerPhotoUploadGrants.ts`), and
 * `storage.rules` verifies that grant at write time. Neither of those steps
 * ever creates the real `CustomerPhoto` moderation record — until now, a
 * successful upload just sat as bytes plus a `status: "issued"` grant that
 * only ever cleared via its 15-minute TTL (P.4.2A's own disclosed gap).
 * This function is the missing conversion: **upload finalized -> exactly
 * one `customerPhotos/{grantId}` record, status `pendingReview`, and the
 * grant marked `consumed` — atomically, idempotently, and only for objects
 * this codebase's own grant record actually authorized.**
 *
 * Scope, stated honestly: this function does **not** approve anything, does
 * not touch `isSelectedAsProfilePhoto`, `customerPublicProfiles`, or
 * `customers.profilePicturePath`. Every photo it creates starts private and
 * unreviewed — moderation/selection is P.4.2B2+.
 *
 * **CR.1.2 (2026-08-20)**: copies the grant's `purpose` straight into the
 * new `customerPhotos` doc — the one and only place that provenance is
 * ever written, server-side, from the server-issued grant, never from
 * anything the client controls at this boundary.
 */

const OBJECT_PATH_PATTERN = /^tenants\/([^/]+)\/customerPhotos\/([^/]+)\/([^/]+)$/;

const CUSTOMER_PHOTOS_COLLECTION = "customerPhotos";
const UPLOAD_GRANTS_COLLECTION = "customerPhotoUploadGrants";
const AUDIT_EVENTS_COLLECTION = "auditEvents";

// How far an object's own `timeCreated` may fall outside the grant's
// [createdAt, expiresAt] window and still be accepted. Both timestamps are
// server-assigned (Google Cloud Storage's own object-creation clock vs.
// this codebase's `Timestamp.now()` at grant-issuance time) — a small
// allowance absorbs ordinary clock/propagation skew between the two
// services without opening a meaningful window for a genuinely
// out-of-grant object to sneak through.
const CLOCK_SKEW_TOLERANCE_MS = 2 * 60 * 1000; // 2 minutes

function db() {
  return getFirestore();
}

interface ParsedCustomerPhotoObjectPath {
  organizationId: string;
  uid: string;
  grantId: string;
}

/**
 * The bucket path is the ONLY thing this function initially trusts about
 * a finalized object — and even that is re-verified against the grant
 * record below rather than trusted outright ("do not trust path values
 * alone"). Any object outside this exact shape is silently ignored: this
 * trigger fires for the whole bucket, and other features (menu images,
 * feedback attachments, import files, ...) finalize objects too.
 */
function parseCustomerPhotoObjectPath(objectName: string): ParsedCustomerPhotoObjectPath | null {
  const match = OBJECT_PATH_PATTERN.exec(objectName);
  if (!match) return null;
  return { organizationId: match[1], uid: match[2], grantId: match[3] };
}

function toMillis(value: Date | string | undefined): number | null {
  if (value == null) return null;
  const ms = value instanceof Date ? value.getTime() : Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Removes an object PROVEN, with certainty (not merely suspected), to
 * have never represented an authorized customer upload — no matching
 * grant, uid/org/path mismatch, or an unsupported content type. Such an
 * object could only exist via a path that bypasses `storage.rules`
 * entirely (direct Admin SDK/console write, or a since-expired grant a
 * client raced against — see the permanent-invalid branches below for
 * exactly which conditions reach this call). It can never legitimately
 * become a `CustomerPhoto`, so leaving unauthorized bytes sitting in a
 * tenant's customer-photo folder serves no purpose and is deleted.
 *
 * Deliberately NOT called for a consumed-grant/generation conflict (see
 * `finalizeCustomerPhotoUpload`'s `"conflict"` branch) — that case is
 * ambiguous enough to warrant preserving the object for manual
 * investigation rather than destroying potential evidence. And never
 * called for a transient failure (a thrown error before this point skips
 * this function entirely and lets the platform retry the whole
 * invocation instead).
 */
async function deleteUnauthorizedObject(bucketName: string, objectName: string, reason: string): Promise<void> {
  try {
    await getStorage().bucket(bucketName).file(objectName).delete({ ignoreNotFound: true });
    logger.warn("[finalizeCustomerPhotoUpload] deleted an unauthorized object", { objectName, reason });
  } catch (err) {
    // Cleanup failing is not itself grounds to retry the whole finalize
    // pass — an orphaned-but-never-authorized object left in place is a
    // smaller problem than an infinite retry loop over a delete that will
    // never succeed. Logged loudly for manual follow-up instead.
    logger.error("[finalizeCustomerPhotoUpload] failed to delete an unauthorized object", {
      objectName,
      reason,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

type FinalizeOutcome =
  | { kind: "created" }
  | { kind: "already-consumed-same-object" }
  | { kind: "permanent-invalid"; reason: string }
  | { kind: "conflict"; reason: string };

/**
 * `retry: true` is a deliberate departure from this codebase's other
 * background triggers (`onOrderCreated`/`onOrderCompleted`), which stay
 * idempotent by design but never ask the platform to retry a thrown
 * error. This function's own correctness DOES depend on that retry: a
 * transient Firestore failure inside the transaction below must not
 * permanently drop a legitimate upload (locked requirement) — it throws,
 * `retry: true` makes Cloud Functions redeliver the same finalize event,
 * and the idempotency design (deterministic `grantId`-keyed photo/grant
 * docs) guarantees the redelivery either completes the original write or
 * safely no-ops if a previous attempt already had.
 */
export const finalizeCustomerPhotoUpload = onObjectFinalized(
  { retry: true },
  async (event: StorageEvent) => {
    const objectName = event.data.name;
    const parsed = parseCustomerPhotoObjectPath(objectName);
    if (!parsed) return; // Not a customer-photo path — ignore safely.

    const { organizationId: pathOrganizationId, uid: pathUid, grantId } = parsed;
    const bucketName = event.data.bucket;
    const contentType = event.data.contentType ?? "";
    const objectGeneration = event.data.generation;
    const timeCreatedMs = toMillis(event.data.timeCreated);

    const grantRef = db().collection(UPLOAD_GRANTS_COLLECTION).doc(grantId);
    const photoRef = db().collection(CUSTOMER_PHOTOS_COLLECTION).doc(grantId);
    // Deterministic per-grant id — a duplicate finalize delivery for the
    // exact same grant always targets the exact same audit document,
    // guaranteeing at most one audit record no matter how many times the
    // event is redelivered (mirrors `onOrderCreated.ts`'s own
    // `auditEvents` shape/idempotency mechanism, the one existing
    // cross-cutting audit collection in this codebase — not a new one).
    const auditRef = db().collection(AUDIT_EVENTS_COLLECTION).doc(`${grantId}-photo-submitted`);

    const outcome: FinalizeOutcome = await db().runTransaction(async (tx) => {
      // Reads before writes, always (this codebase's own transaction
      // discipline — reservationHoldOps.ts/assignReservationTable.ts).
      const [grantSnap, photoSnap] = await Promise.all([tx.get(grantRef), tx.get(photoRef)]);

      if (!grantSnap.exists) {
        return { kind: "permanent-invalid", reason: "no-matching-grant" };
      }
      const grant = grantSnap.data()!;

      if (grant.status === "consumed") {
        if (grant.photoId === grantId && grant.objectGeneration === objectGeneration) {
          // Duplicate delivery of an event this function already fully
          // processed — safe no-op, not an error.
          return { kind: "already-consumed-same-object" };
        }
        // The grant was already consumed by a DIFFERENT object/generation
        // than the one this event describes. This should be unreachable
        // under normal operation (a grant authorizes exactly one path,
        // and `storage.rules`' own `resource == null` makes that path
        // single-use) — reaching it means something bypassed the normal
        // authorized path. Do not mutate any record; preserve everything
        // exactly as-is for manual investigation.
        return { kind: "conflict", reason: "consumed-grant-generation-conflict" };
      }

      if (grant.uid !== pathUid || grant.organizationId !== pathOrganizationId) {
        // The object's own path claims one uid/org; the grant looked up
        // by this exact grantId says another. Path segments are never
        // authorization truth by themselves — the grant record is.
        return { kind: "permanent-invalid", reason: "uid-or-organization-mismatch" };
      }
      const expectedObjectPath = `tenants/${pathOrganizationId}/customerPhotos/${pathUid}/${grantId}`;
      if (grant.objectPath !== expectedObjectPath || objectName !== expectedObjectPath) {
        return { kind: "permanent-invalid", reason: "object-path-mismatch" };
      }
      if (!contentType.startsWith("image/")) {
        return { kind: "permanent-invalid", reason: "unsupported-content-type" };
      }
      if (typeof grant.contentType === "string" && grant.contentType !== contentType) {
        return { kind: "permanent-invalid", reason: "content-type-does-not-match-grant" };
      }
      if (timeCreatedMs == null) {
        return { kind: "permanent-invalid", reason: "missing-object-creation-timestamp" };
      }
      const grantCreatedAtMs = (grant.createdAt as Timestamp).toMillis();
      const grantExpiresAtMs = (grant.expiresAt as Timestamp).toMillis();
      // The object must have been created within the grant's own
      // authorized window — evaluated against the object's OWN immutable
      // creation timestamp, never against "now". This function can run
      // arbitrarily later than the actual upload (event delivery lag,
      // retries); a legitimate upload made while the grant was valid must
      // still be accepted even if `expiresAt` has since passed by the
      // time this code runs. An object whose OWN creation time falls
      // outside the grant's window, by contrast, was never authorized by
      // `storage.rules` at write time — the only way it can exist is a
      // bypass (Admin SDK/console), and it is rejected regardless of when
      // this function happens to process it.
      if (
        timeCreatedMs < grantCreatedAtMs - CLOCK_SKEW_TOLERANCE_MS ||
        timeCreatedMs > grantExpiresAtMs + CLOCK_SKEW_TOLERANCE_MS
      ) {
        return { kind: "permanent-invalid", reason: "object-created-outside-grant-window" };
      }
      if (photoSnap.exists) {
        // A photo already exists at this deterministic id without the
        // grant having been marked consumed — should not be reachable
        // given grantId is this photoId's sole producer, but a
        // deterministic id must never be blindly overwritten.
        return { kind: "conflict", reason: "photo-id-already-exists-without-consumed-grant" };
      }

      const now = Timestamp.now();
      tx.set(photoRef, {
        customerId: pathUid,
        organizationId: pathOrganizationId,
        // Opaque Storage object path — never raw bytes, never a public
        // download URL, mirroring `CustomerPhoto.photoRef`'s existing
        // domain-layer discipline.
        photoRef: objectName,
        status: "pendingReview",
        isSelectedAsProfilePhoto: false,
        uploadedAt: now,
        reviewedByStaffId: null,
        reviewedAt: null,
        rejectionReason: null,
        revision: 1,
        // CR.1.2 — copied straight from the grant this object was
        // authorized against, never trusted from the client at this
        // boundary (there is no client input to this trigger at all).
        // `moderateCustomerPhoto.ts` reads this to decide auto-selection.
        purpose: grant.purpose ?? null,
      });
      tx.update(grantRef, {
        status: "consumed",
        consumedAt: now,
        photoId: grantId,
        objectGeneration,
      });
      tx.set(auditRef, {
        organizationId: pathOrganizationId,
        uid: pathUid,
        photoId: grantId,
        grantId,
        type: "customerPhoto.submitted",
        actor: "system",
        timestamp: now,
      });

      return { kind: "created" };
    });

    switch (outcome.kind) {
      case "created":
        logger.info("[finalizeCustomerPhotoUpload] customer photo created", {
          objectName,
          grantId,
          organizationId: pathOrganizationId,
          uid: pathUid,
        });
        return;
      case "already-consumed-same-object":
        logger.info("[finalizeCustomerPhotoUpload] duplicate finalize event — already processed, no-op", {
          objectName,
          grantId,
        });
        return;
      case "conflict":
        logger.error(
          "[finalizeCustomerPhotoUpload] integrity conflict — no records mutated, manual review required",
          { objectName, grantId, reason: outcome.reason },
        );
        return;
      case "permanent-invalid":
        logger.warn(
          "[finalizeCustomerPhotoUpload] rejecting an object that was never a valid grant-authorized upload",
          { objectName, grantId, reason: outcome.reason },
        );
        await deleteUnauthorizedObject(bucketName, objectName, outcome.reason);
        return;
    }
  },
);
