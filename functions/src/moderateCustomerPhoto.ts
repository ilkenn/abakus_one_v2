import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import type { DocumentReference } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission } from "./staffAuthorization";

/**
 * `moderateCustomerPhoto` — Profile P.4.2B2 (2026-08-19).
 *
 * The server-authoritative counterpart of the Dart `ModerateCustomerPhoto`
 * use case (`lib/features/admin/application/use_cases/
 * moderate_customer_photo.dart`) — same 4 actions mapping to the same
 * `CustomerPhotoStatus` targets (never a different state machine), but
 * enforced against the real `customerPhotos` Firestore collection
 * (`allow write: if false` in `firestore.rules` — Admin SDK/Cloud Function
 * only) rather than an in-memory repository, with real staff-role
 * authorization instead of the Dart-only `PosAuthorizationPolicy` that has
 * no server enforcement behind it today.
 *
 * **Authorization never trusts a client-supplied organizationId or role.**
 * The target photo's own `organizationId` is read from Firestore first;
 * `requireStaffPermission` then checks the CALLER's `roles`/
 * `organizationAccess` custom claims against THAT organization — a staff
 * member of a different tenant can never moderate this photo no matter
 * what they claim in the request body.
 *
 * **Terminal state**: `removed` never transitions to anything else. Every
 * other (status, action) pair is permitted, mirroring the Dart use case's
 * own permissiveness — this is the one deliberate tightening beyond it,
 * disclosed here rather than silently invented: the in-memory Dart use
 * case has no reason to guard against "resurrecting" a removed photo
 * (nothing depends on it), but a real server enforcing this lifecycle
 * should not allow a removed photo to become visible again.
 *
 * **Idempotent replay**: if the requested action would produce a status
 * (and, for `reject`, a rejection reason) identical to the photo's CURRENT
 * state, this is treated as a no-op success — no write, no revision bump,
 * no audit entry. A genuinely different follow-up action (even to the
 * same target status with a different reason) still processes normally.
 *
 * **Clearing a public selection is part of the SAME transaction**, never
 * a follow-up step: if the photo being moderated is currently the
 * customer's selected profile photo and the new status is not `approved`,
 * this transaction also clears `isSelectedAsProfilePhoto` and (if the
 * projection still points at this exact photo) `customerPublicProfiles
 * .selectedProfilePhotoRef` — no transient state ever leaves a
 * rejected/removed photo publicly selected. No automatic replacement is
 * chosen; the customer selects a new one later via
 * `selectCustomerProfilePhoto`.
 */

export type CustomerPhotoModerationAction = "approve" | "reject" | "remove" | "returnToReview";

const ACTION_TO_STATUS: Record<CustomerPhotoModerationAction, string> = {
  approve: "approved",
  reject: "rejected",
  remove: "removed",
  returnToReview: "underReview",
};

const VALID_ACTIONS = new Set<string>(Object.keys(ACTION_TO_STATUS));

interface ModerateCustomerPhotoResult {
  photoId: string;
  status: string;
  revision: number;
  idempotent: boolean;
  clearedPublicSelection: boolean;
}

function db() {
  return getFirestore();
}

export const moderateCustomerPhoto = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<ModerateCustomerPhotoResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }

    const photoId = request.data?.photoId;
    if (typeof photoId !== "string" || photoId.length === 0) {
      throw new HttpsError("invalid-argument", "photoId is required.");
    }
    const action = request.data?.action;
    if (typeof action !== "string" || !VALID_ACTIONS.has(action)) {
      throw new HttpsError(
        "invalid-argument",
        `action must be one of: ${Array.from(VALID_ACTIONS).join(", ")}.`,
      );
    }
    const rejectionReasonRaw = request.data?.rejectionReason;
    const rejectionReason =
      typeof rejectionReasonRaw === "string" && rejectionReasonRaw.length > 0
        ? rejectionReasonRaw
        : null;

    const moderationAction = action as CustomerPhotoModerationAction;
    const newStatus = ACTION_TO_STATUS[moderationAction];
    const staffUid = request.auth.uid;

    const photoRef = db().collection("customerPhotos").doc(photoId);

    const result = await db().runTransaction(async (tx): Promise<ModerateCustomerPhotoResult> => {
      const photoSnap = await tx.get(photoRef);
      if (!photoSnap.exists) {
        throw new HttpsError("not-found", "Customer photo not found.");
      }
      const photo = photoSnap.data()!;
      const organizationId = photo.organizationId as string;

      // Server-authoritative role check against the PHOTO's own
      // organization — never a client-supplied one. Throws
      // unauthenticated/permission-denied, which aborts the transaction.
      requireStaffPermission(request, organizationId, "moderateCustomerPhotos");

      const currentStatus = photo.status as string;
      const currentRejectionReason = (photo.rejectionReason ?? null) as string | null;

      // Idempotent replay — same target status (and, for reject, the same
      // reason) as what's already stored. No write, no audit.
      const isIdempotentReplay =
        currentStatus === newStatus &&
        (moderationAction !== "reject" || currentRejectionReason === rejectionReason);
      if (isIdempotentReplay) {
        return {
          photoId,
          status: currentStatus,
          revision: photo.revision as number,
          idempotent: true,
          clearedPublicSelection: false,
        };
      }

      // `removed` is terminal — never resurrected into any other status.
      if (currentStatus === "removed") {
        throw new HttpsError(
          "failed-precondition",
          "A removed customer photo can never transition to another status.",
        );
      }

      const wasSelected = photo.isSelectedAsProfilePhoto === true;
      const clearsSelection = wasSelected && newStatus !== "approved";

      let clearedPublicSelection = false;
      let projectionRef: DocumentReference | null = null;
      if (clearsSelection) {
        projectionRef = db()
          .collection("customerPublicProfiles")
          .doc(`${organizationId}_${photo.customerId}`);
        const projectionSnap = await tx.get(projectionRef);
        if (projectionSnap.exists && projectionSnap.data()!.selectedProfilePhotoRef === photo.photoRef) {
          clearedPublicSelection = true;
        }
      }

      const now = Timestamp.now();
      const newRevision = (photo.revision as number) + 1;

      tx.update(photoRef, {
        status: newStatus,
        isSelectedAsProfilePhoto: clearsSelection ? false : photo.isSelectedAsProfilePhoto,
        reviewedByStaffId: staffUid,
        reviewedAt: now,
        rejectionReason: moderationAction === "reject" ? rejectionReason : null,
        revision: newRevision,
      });

      if (clearedPublicSelection && projectionRef) {
        tx.set(
          projectionRef,
          { selectedProfilePhotoRef: null, updatedAt: now },
          { merge: true },
        );
      }

      // Deterministic per-transition id (photoId + the NEW revision it
      // produces) — a genuine second distinct transition always gets a
      // distinct revision, so this can never collide with a prior
      // transition's own audit entry; a Firestore-internal contention
      // retry recomputes the identical id on each attempt, so only the
      // one attempt that actually commits ever persists an entry.
      const auditRef = db().collection("auditEvents").doc(`${photoId}-moderation-rev${newRevision}`);
      tx.set(auditRef, {
        organizationId,
        actorStaffId: staffUid,
        customerId: photo.customerId,
        photoId,
        action: moderationAction,
        beforeStatus: currentStatus,
        afterStatus: newStatus,
        clearedPublicSelection,
        revision: newRevision,
        type: "customerPhoto.moderated",
        timestamp: now,
      });

      return {
        photoId,
        status: newStatus,
        revision: newRevision,
        idempotent: false,
        clearedPublicSelection,
      };
    });

    logger.info("[moderateCustomerPhoto] processed", {
      photoId,
      action: moderationAction,
      staffUid,
      idempotent: result.idempotent,
      clearedPublicSelection: result.clearedPublicSelection,
    });

    return result;
  },
);
