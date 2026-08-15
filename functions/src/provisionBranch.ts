import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { requirePlatformMember } from "./platformAuthorization";

/**
 * Server-authoritative `branches` provisioning — Faz D.1. See
 * `provisionRestaurant`'s own doc comment for the shared authorization/
 * idempotency reasoning; this function additionally enforces the one
 * piece of chain verification Faz D.1's request explicitly requires: a
 * branch's claimed `organizationId`/`restaurantId` are **never trusted
 * from the caller alone**. The parent `restaurants/{restaurantId}`
 * document is read server-side, inside the same transaction, and its own
 * `organizationId` must match exactly — mirrors
 * `docs/firestore_data_model.md`'s documented "branch scope resolves
 * through branch -> restaurant -> organization... verified once at
 * `branches` document creation via `get()` on the parent `restaurants`
 * document" design. A caller that supplies a real `restaurantId` but a
 * mismatched `organizationId` (by mistake or as a deliberate cross-tenant
 * attempt) is rejected before any write happens — no branch document is
 * ever created for an unverified parent.
 *
 * A missing parent restaurant (never provisioned, or a typo'd id) is
 * rejected the same way — `provisionBranch` never creates an implicit
 * `restaurants` document to "fill the gap"; the chain must be built in
 * order, restaurant first.
 *
 * Idempotency follows `provisionRestaurant`'s exact same shape:
 * caller-supplied deterministic `branchId`, `.set()`-based upsert,
 * immutable `organizationId`/`restaurantId` binding once first set.
 */
export const provisionBranch = onCall(async (request) => {
  requirePlatformMember(request);

  const data = request.data ?? {};
  const organizationId = data.organizationId;
  const restaurantId = data.restaurantId;
  const branchId = data.branchId;
  const name = data.name;
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    throw new HttpsError("invalid-argument", "organizationId is required.");
  }
  if (typeof restaurantId !== "string" || restaurantId.length === 0) {
    throw new HttpsError("invalid-argument", "restaurantId is required.");
  }
  if (typeof branchId !== "string" || branchId.length === 0) {
    throw new HttpsError("invalid-argument", "branchId is required.");
  }
  if (typeof name !== "string" || name.length === 0) {
    throw new HttpsError("invalid-argument", "name is required.");
  }
  const supportedOrderChannelIds = Array.isArray(data.supportedOrderChannelIds)
    ? data.supportedOrderChannelIds
    : [];
  const timezone = typeof data.timezone === "string" ? data.timezone : "Europe/Istanbul";
  const currencyCode = typeof data.currencyCode === "string" ? data.currencyCode : "TRY";
  const localeCode = typeof data.localeCode === "string" ? data.localeCode : "tr";
  const status = typeof data.status === "string" ? data.status : "active";

  const db = getFirestore();
  const restaurantRef = db.collection("restaurants").doc(restaurantId);
  const branchRef = db.collection("branches").doc(branchId);
  const now = new Date();

  const { created } = await db.runTransaction(async (tx) => {
    const restaurantDoc = await tx.get(restaurantRef);
    if (!restaurantDoc.exists) {
      throw new HttpsError(
        "failed-precondition",
        `Parent restaurant "${restaurantId}" does not exist — provision it ` +
          "first via provisionRestaurant.",
      );
    }
    const restaurantData = restaurantDoc.data()!;
    if (restaurantData.organizationId !== organizationId) {
      throw new HttpsError(
        "failed-precondition",
        `Parent restaurant "${restaurantId}" belongs to a different ` +
          "organization than the one claimed for this branch.",
      );
    }

    const existing = await tx.get(branchRef);
    if (existing.exists) {
      const existingData = existing.data()!;
      if (
        existingData.organizationId !== organizationId ||
        existingData.restaurantId !== restaurantId
      ) {
        throw new HttpsError(
          "failed-precondition",
          `branchId "${branchId}" already belongs to a different ` +
            "organization/restaurant — a branch's tenant binding is immutable.",
        );
      }
      tx.set(
        branchRef,
        {
          organizationId,
          restaurantId,
          name,
          status,
          supportedOrderChannelIds,
          timezone,
          currencyCode,
          localeCode,
          updatedAt: now,
          revision: FieldValue.increment(1),
        },
        { merge: true },
      );
      return { created: false };
    }

    tx.set(branchRef, {
      organizationId,
      restaurantId,
      name,
      status,
      supportedOrderChannelIds,
      timezone,
      currencyCode,
      localeCode,
      emergencyStopped: false,
      createdAt: now,
      updatedAt: now,
      revision: 1,
    });
    return { created: true };
  });

  return { branchId, restaurantId, organizationId, created };
});
