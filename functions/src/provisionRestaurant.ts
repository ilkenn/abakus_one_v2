import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { requirePlatformMember } from "./platformAuthorization";

/**
 * Server-authoritative `restaurants` provisioning — Faz D.1 (Canonical
 * Restaurant/Branch Provisioning, Gel Al architecture analysis). Closes
 * the "Cloud Function only" gap `firestore.rules`'s own `restaurants`
 * match block has anticipated since Phase 9 (`allow write: if false //
 * Cloud Function only`) and `docs/firestore_data_model.md` already
 * specifies the row shape for — this is the first Function that actually
 * writes to it.
 *
 * **Authorization**: Platform Owner/Administrator only, via
 * [requirePlatformMember] — never public/anonymous-callable. Restaurant
 * provisioning is tenant-onboarding, a platform-level action.
 *
 * **`organizationId` chain verification (Faz D.1.1)**: a caller-supplied
 * `organizationId` is never authoritative on its own — this function reads
 * `organizations/{organizationId}` server-side, inside the same
 * transaction, and requires it to both exist and have `isActive == true`
 * before a restaurant may be provisioned under it. Closes Faz D.1's one
 * REQUIRED finding (previously: structural string validation only). A
 * caller claiming an `organizationId` that was never provisioned via
 * `provisionOrganization`, or one that has been deactivated, is rejected
 * before any restaurant document is written.
 *
 * **Idempotency note**: an *existing* restaurant's own immutable
 * `organizationId` binding (below) is still checked first for an
 * already-provisioned `restaurantId` — the organization-liveness check
 * applies to every call (new or re-provision), since a previously-valid
 * organization could in principle have been deactivated since the
 * restaurant was first created.
 *
 * **Idempotency**: `restaurantId` is a caller-supplied, deterministic
 * document id — mirrors `Order.id`'s own "external id, `.set()` is the
 * idempotent-overwrite mechanism" convention already established in this
 * codebase (`CanonicalOrderRepository`/`SubmitCustomerOrder`), not a
 * Firestore auto-generated id. Calling this twice with the same
 * `restaurantId` and the same `organizationId` upserts the same single
 * document — never a duplicate. Calling it again for an existing
 * `restaurantId` with a *different* `organizationId` is rejected outright
 * (`failed-precondition`): a restaurant's tenant binding, once set, is
 * immutable, mirroring `organizationIdUnchanged()`'s own rule for every
 * other tenant-owned document in `firestore.rules`.
 */
export const provisionRestaurant = onCall(async (request) => {
  requirePlatformMember(request);

  const data = request.data ?? {};
  const organizationId = data.organizationId;
  const restaurantId = data.restaurantId;
  const name = data.name;
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    throw new HttpsError("invalid-argument", "organizationId is required.");
  }
  if (typeof restaurantId !== "string" || restaurantId.length === 0) {
    throw new HttpsError("invalid-argument", "restaurantId is required.");
  }
  if (typeof name !== "string" || name.length === 0) {
    throw new HttpsError("invalid-argument", "name is required.");
  }
  const defaultLanguageCode =
    typeof data.defaultLanguageCode === "string" ? data.defaultLanguageCode : "tr";
  const supportedLanguageCodes = Array.isArray(data.supportedLanguageCodes)
    ? data.supportedLanguageCodes
    : ["tr"];
  const isActive = typeof data.isActive === "boolean" ? data.isActive : true;

  const db = getFirestore();
  const organizationRef = db.collection("organizations").doc(organizationId);
  const ref = db.collection("restaurants").doc(restaurantId);
  const now = new Date();

  const { created } = await db.runTransaction(async (tx) => {
    const organizationDoc = await tx.get(organizationRef);
    if (!organizationDoc.exists) {
      throw new HttpsError(
        "failed-precondition",
        `Organization "${organizationId}" does not exist — provision it ` +
          "first via provisionOrganization.",
      );
    }
    if (organizationDoc.data()!.isActive !== true) {
      throw new HttpsError(
        "failed-precondition",
        `Organization "${organizationId}" is not active.`,
      );
    }

    const existing = await tx.get(ref);
    if (existing.exists) {
      const existingData = existing.data()!;
      if (existingData.organizationId !== organizationId) {
        throw new HttpsError(
          "failed-precondition",
          `restaurantId "${restaurantId}" already belongs to a different ` +
            "organization — a restaurant's tenant binding is immutable.",
        );
      }
      tx.set(
        ref,
        {
          organizationId,
          name,
          defaultLanguageCode,
          supportedLanguageCodes,
          isActive,
          updatedAt: now,
          revision: FieldValue.increment(1),
        },
        { merge: true },
      );
      return { created: false };
    }

    tx.set(ref, {
      organizationId,
      name,
      defaultLanguageCode,
      supportedLanguageCodes,
      isActive,
      createdAt: now,
      updatedAt: now,
      revision: 1,
    });
    return { created: true };
  });

  return { restaurantId, organizationId, created };
});
