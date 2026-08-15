import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { requirePlatformMember } from "./platformAuthorization";

/**
 * Server-authoritative `organizations` provisioning — Faz D.1.1 (Canonical
 * Organization Provisioning, closing Faz D.1's one REQUIRED finding).
 * `organizations` is the top of the tenant hierarchy
 * (`docs/firestore_data_model.md`) — no parent to verify a chain against,
 * unlike `provisionRestaurant`/`provisionBranch`; provisioning one *is*
 * establishing a new tenant boundary, which is exactly why it stays
 * Platform Owner/Administrator-only, identical to those two functions'
 * own authorization ([requirePlatformMember]) — never public/
 * anonymous-callable, and never satisfiable by a tenant-level
 * `roles`/`organizationAccess` claim, however senior within its own
 * tenant (that claim namespace is deliberately never read here at all).
 *
 * **Idempotency**: `organizationId` is a caller-supplied, deterministic
 * document id (same convention as `provisionRestaurant`/`provisionBranch`)
 * — calling this twice upserts the same single document (`revision`
 * increments), never a duplicate. Unlike restaurant/branch, there is no
 * parent-binding field to make immutable here — an organization's `name`/
 * `isActive` may be legitimately re-provisioned (e.g. correcting a typo,
 * or a platform admin deactivating a tenant) without that being a
 * cross-tenant reassignment risk, since the document's own id *is* the
 * tenant boundary and never changes.
 *
 * **`isActive`** (default `true`) is the field `provisionRestaurant` now
 * checks before allowing a restaurant to be provisioned under this
 * organization — mirrors `Restaurant.isActive`'s own boolean convention
 * (the `Organization` Dart domain model itself has no status field yet;
 * this is Firestore-canonical-only for now, additive, not a Dart model
 * change this phase).
 */
export const provisionOrganization = onCall(async (request) => {
  requirePlatformMember(request);

  const data = request.data ?? {};
  const organizationId = data.organizationId;
  const name = data.name;
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    throw new HttpsError("invalid-argument", "organizationId is required.");
  }
  if (typeof name !== "string" || name.length === 0) {
    throw new HttpsError("invalid-argument", "name is required.");
  }
  const isActive = typeof data.isActive === "boolean" ? data.isActive : true;

  const db = getFirestore();
  const ref = db.collection("organizations").doc(organizationId);
  const now = new Date();

  const { created } = await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) {
      tx.set(
        ref,
        { name, isActive, updatedAt: now, revision: FieldValue.increment(1) },
        { merge: true },
      );
      return { created: false };
    }

    tx.set(ref, {
      name,
      isActive,
      createdAt: now,
      updatedAt: now,
      revision: 1,
    });
    return { created: true };
  });

  return { organizationId, created };
});
