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
 *
 * **Auto-selection on approval — Customer Registration CR.1.2
 * (2026-08-20).** When an `approve` action targets a photo whose
 * server-authoritative `purpose` (set once, at finalize, from the upload
 * grant — never client-supplied here) is `"profileOnboarding"`, AND the
 * customer currently has no `selectedProfilePhotoRef` at all
 * (`customerPublicProfiles/{organizationId}_{customerId}` missing, or
 * present with no pointer), this SAME transaction also sets
 * `isSelectedAsProfilePhoto: true` on the photo and writes the projection
 * — the customer's very first onboarding photo becomes their canonical
 * profile photo the moment it clears review, with no extra customer
 * action. If a selection already exists, this branch never runs — an
 * older onboarding photo's approval can never displace an already-chosen
 * newer selection. Transaction-safety and "exactly one canonical winner"
 * under a concurrent manual `selectCustomerProfilePhoto` call fall out of
 * Firestore's own optimistic-concurrency retry semantics for free (both
 * paths read-then-write the same projection doc inside their own
 * transaction), the same reasoning already established for this
 * codebase's other transactional invariants. Audited via a dedicated,
 * deterministic `auditEvents/{photoId}-auto-selected` entry
 * (`actorId: "system"`, mirroring `finalizeCustomerPhotoUpload`'s own
 * system-actor convention) — never silently folded into the moderation
 * audit entry alone.
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
  autoSelected: boolean;
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
          autoSelected: false,
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

      // CR.1.2 — auto-selection on approval. Only ever considered for a
      // genuine approve transition (never reachable for the idempotent-
      // replay case above, which already short-circuited) whose photo
      // carries the server-authoritative onboarding intent, and only when
      // the customer has no existing public selection to protect.
      const isApproving = newStatus === "approved";
      const hasOnboardingIntent = photo.purpose === "profileOnboarding";
      let autoSelected = false;
      let autoSelectProjectionRef: DocumentReference | null = null;
      if (isApproving && hasOnboardingIntent) {
        autoSelectProjectionRef = db()
          .collection("customerPublicProfiles")
          .doc(`${organizationId}_${photo.customerId}`);
        const projectionSnap = await tx.get(autoSelectProjectionRef);
        const hasExistingSelection =
          projectionSnap.exists && !!projectionSnap.data()!.selectedProfilePhotoRef;
        autoSelected = !hasExistingSelection;
      }

      const now = Timestamp.now();
      const newRevision = (photo.revision as number) + 1;

      tx.update(photoRef, {
        status: newStatus,
        isSelectedAsProfilePhoto: clearsSelection
          ? false
          : autoSelected
              ? true
              : photo.isSelectedAsProfilePhoto,
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

      if (autoSelected && autoSelectProjectionRef) {
        tx.set(
          autoSelectProjectionRef,
          {
            uid: photo.customerId,
            organizationId,
            selectedProfilePhotoRef: photo.photoRef,
            updatedAt: now,
          },
          { merge: true },
        );
        // Deterministic per-photo id — a redelivered/retried transaction
        // attempt recomputes the identical id, so only the one attempt
        // that actually commits ever persists this entry.
        const autoSelectAuditRef = db().collection("auditEvents").doc(`${photoId}-auto-selected`);
        tx.set(autoSelectAuditRef, {
          organizationId,
          uid: photo.customerId,
          actorId: "system",
          photoId,
          previousSelectedPhotoId: null,
          type: "customerPhoto.selected",
          autoSelectedViaModeration: true,
          timestamp: now,
        });
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
        autoSelected,
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
        autoSelected,
      };
    });

    logger.info("[moderateCustomerPhoto] processed", {
      photoId,
      action: moderationAction,
      staffUid,
      idempotent: result.idempotent,
      clearedPublicSelection: result.clearedPublicSelection,
      autoSelected: result.autoSelected,
    });

    return result;
  },
);
