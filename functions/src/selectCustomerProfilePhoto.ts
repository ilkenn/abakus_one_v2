import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * `selectCustomerProfilePhoto` — Profile P.4.2B2 (2026-08-19).
 *
 * Closes the ownership gap `select_customer_profile_photo.dart` itself
 * has documented since P.4/P.4.1 audits: "No authorization gate —
 * self-service, the customer's own choice" was true of the in-memory Dart
 * use case, but nothing server-side ever re-enforced it. This callable
 * IS that server-side boundary — the Dart use case's own defense-in-depth
 * ownership check (added alongside this file) is a second line, never
 * the actual security boundary; only this callable, backed by
 * `firestore.rules`' `customerPhotos`/`customerPublicProfiles` `allow
 * write: if false`, is.
 *
 * **Canonical selected-photo source — locked correction from P.4.1's own
 * plan**: `customers/{uid}.profilePicturePath` is never written here (it
 * stays non-client-writable and is not treated as canonical for anything
 * — it is a single GLOBAL field on the customer identity, unsafe as the
 * source of a TENANT-scoped selection). The one canonical, public-safe
 * source is `customerPublicProfiles/{organizationId}_{uid}
 * .selectedProfilePhotoRef` — already P.4.1's own minimal projection,
 * now actually written to for the first time.
 *
 * **No extra internal-pointer field was added to the projection.** The
 * previously-selected photo (if any) is found via an in-transaction query
 * (`customerPhotos` where `customerId`/`organizationId`/
 * `isSelectedAsProfilePhoto==true`) rather than a stored pointer — this
 * codebase already establishes `tx.get(query)` as a safe, existing
 * pattern (`customerPhotoUploadGrants.ts`'s own quota query), and it
 * avoids adding server-only metadata to a document real staff/customers
 * can otherwise read the whole of. Concurrency safety does not depend on
 * that query's own conflict detection — every selection transaction also
 * reads-then-writes the projection document itself, and Firestore
 * automatically retries the whole transaction body (query included) on a
 * conflicting commit, so a losing transaction re-observes the winner's
 * already-updated state on its retry rather than racing against stale
 * data.
 *
 * **Idempotent**: selecting the photo that is already the customer's
 * selected profile photo is a no-op success — no revision bump, no
 * duplicate audit entry.
 */

interface SelectCustomerProfilePhotoResult {
  photoId: string;
  photoRef: string;
  idempotent: boolean;
}

function db() {
  return getFirestore();
}

export const selectCustomerProfilePhoto = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<SelectCustomerProfilePhotoResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Selecting a profile photo requires a real, phone-verified customer identity.",
      );
    }
    const uid = request.auth.uid;

    const photoId = request.data?.photoId;
    if (typeof photoId !== "string" || photoId.length === 0) {
      throw new HttpsError("invalid-argument", "photoId is required.");
    }
    const organizationId = request.data?.organizationId;
    if (typeof organizationId !== "string" || organizationId.length === 0) {
      throw new HttpsError("invalid-argument", "organizationId is required.");
    }

    // Never trust the client's organizationId as authorization truth on
    // its own — independently verify real tenant membership, same
    // mechanism `requestCustomerPhotoUploadGrant` already uses.
    const tenantCustomerDoc = await db()
      .collection("tenantCustomers")
      .doc(`${organizationId}_${uid}`)
      .get();
    if (!tenantCustomerDoc.exists) {
      throw new HttpsError("permission-denied", "You are not a customer of this organization.");
    }

    const photoRef = db().collection("customerPhotos").doc(photoId);
    const projectionRef = db().collection("customerPublicProfiles").doc(`${organizationId}_${uid}`);

    const result = await db().runTransaction(
      async (tx): Promise<SelectCustomerProfilePhotoResult> => {
        // Reads before writes: target photo, the projection (may not
        // exist yet), and every OTHER currently-selected photo of this
        // same customer within this same tenant.
        const [photoSnap, projectionSnap, currentlySelectedSnap] = await Promise.all([
          tx.get(photoRef),
          tx.get(projectionRef),
          tx.get(
            db()
              .collection("customerPhotos")
              .where("customerId", "==", uid)
              .where("organizationId", "==", organizationId)
              .where("isSelectedAsProfilePhoto", "==", true),
          ),
        ]);

        if (!photoSnap.exists) {
          throw new HttpsError("not-found", "Customer photo not found.");
        }
        const photo = photoSnap.data()!;

        // Ownership: caller may select ONLY their own photo.
        if (photo.customerId !== uid) {
          throw new HttpsError("permission-denied", "You may only select your own photo.");
        }
        // Tenant scope: the photo must belong to the requested/current
        // tenant — a cross-tenant photoId can never be selected here
        // even if (implausibly) it also happened to belong to this uid.
        if (photo.organizationId !== organizationId) {
          throw new HttpsError("permission-denied", "This photo does not belong to the requested organization.");
        }
        if (photo.status !== "approved") {
          throw new HttpsError(
            "failed-precondition",
            "Only an approved photo may be selected as the profile photo.",
          );
        }

        const projectionData = projectionSnap.exists ? projectionSnap.data()! : null;
        if (projectionData?.selectedProfilePhotoRef === photo.photoRef) {
          // Already selected — idempotent success, no mutation.
          return { photoId, photoRef: photo.photoRef as string, idempotent: true };
        }

        const now = Timestamp.now();

        for (const doc of currentlySelectedSnap.docs) {
          if (doc.id === photoId) continue; // defensive — shouldn't appear given the check above.
          const sibling = doc.data();
          tx.update(doc.ref, {
            isSelectedAsProfilePhoto: false,
            revision: (sibling.revision as number) + 1,
          });
        }

        tx.update(photoRef, {
          isSelectedAsProfilePhoto: true,
          revision: (photo.revision as number) + 1,
        });

        tx.set(
          projectionRef,
          {
            uid,
            organizationId,
            selectedProfilePhotoRef: photo.photoRef,
            updatedAt: now,
          },
          { merge: true },
        );

        tx.set(db().collection("auditEvents").doc(), {
          organizationId,
          uid,
          actorId: uid,
          photoId,
          previousSelectedPhotoId: currentlySelectedSnap.docs.find((d) => d.id !== photoId)?.id ?? null,
          type: "customerPhoto.selected",
          timestamp: now,
        });

        return { photoId, photoRef: photo.photoRef as string, idempotent: false };
      },
    );

    logger.info("[selectCustomerProfilePhoto] processed", {
      uid,
      organizationId,
      photoId,
      idempotent: result.idempotent,
    });

    return result;
  },
);
