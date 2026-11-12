import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { slugifyAddressComponent } from "./deliveryServiceAreas";
import { COURIER_ACCOUNTS_COLLECTION } from "./courierPool";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * AP-6 Sprint 2 — the minimal roster-seeding plumbing for `couriers/
 * {courierId}`: upsert-with-revision, mirrors `setStandardIngredientCost.ts`'s
 * exact shape. No full roster-management screen exists this sprint (out of
 * scope, not requested) — staff register a courier through
 * `CourierAssignmentDialog`'s own lightweight inline quick-add, which calls
 * this callable directly.
 *
 * `courierId` is client-supplied (the quick-add form generates one, or an
 * existing courier is being edited) so a retry with the same id is a pure
 * idempotent upsert, never a duplicate — same discipline every other AP-5/6
 * upsert callable already follows.
 */

const VALID_TYPES = ["internal", "pool", "marketplace"] as const;
const VALID_VEHICLE_TYPES = ["bicycle", "motorcycle", "car", "onFoot"] as const;
const VALID_DISPATCH_STATUSES = ["available", "delivering", "offline"] as const;
const VALID_REGISTRY_STATUSES = ["active", "suspended", "archived"] as const;

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  return value;
}

function optionalEnum<T extends string>(
  value: unknown,
  allowed: readonly T[],
  field: string,
  fallback: T,
): T {
  if (value === undefined || value === null) return fallback;
  if (typeof value !== "string" || !(allowed as readonly string[]).includes(value)) {
    throw new HttpsError("invalid-argument", `${field} must be one of: ${allowed.join(", ")}.`);
  }
  return value as T;
}

export const setCourier = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const branchId = requireString(data.branchId, "branchId");
    const displayName = requireString(data.displayName, "displayName");
    const phoneNumber = requireString(data.phoneNumber, "phoneNumber");
    const courierId =
      typeof data.courierId === "string" && data.courierId.length > 0
        ? data.courierId
        : undefined;

    const type = optionalEnum(data.type, VALID_TYPES, "type", "internal");
    const vehicleType = optionalEnum(
      data.vehicleType,
      VALID_VEHICLE_TYPES,
      "vehicleType",
      "motorcycle",
    );
    const dispatchStatus = optionalEnum(
      data.dispatchStatus,
      VALID_DISPATCH_STATUSES,
      "dispatchStatus",
      "offline",
    );
    const status = optionalEnum(data.status, VALID_REGISTRY_STATUSES, "status", "active");
    const vehicleIdentifier =
      typeof data.vehicleIdentifier === "string" ? data.vehicleIdentifier : "";
    const capacity =
      typeof data.capacity === "number" && Number.isInteger(data.capacity) && data.capacity > 0
        ? data.capacity
        : 1;

    await requireStaffPermission(request, organizationId, "manageCourierDispatch");

    // 2026-11-12 (Faz 3a) — external (`pool`) couriers: registered by a
    // manager or above only (`manageBranch`, manager/admin/tenantOwner),
    // with the districts (`serviceDistrictIds`, slugs) whose pool packages
    // they see, and optionally the auth account they sign in with
    // (`authUid`, mirrored to `courierAccounts/{uid}`). `authUid`: absent =
    // keep the current link, "" or null = unlink.
    if (type === "pool") {
      await requireStaffPermission(request, organizationId, "manageBranch");
    }
    const rawDistricts = Array.isArray(data.serviceDistrictIds) ? data.serviceDistrictIds : [];
    if (rawDistricts.length > 30) {
      throw new HttpsError("invalid-argument", "serviceDistrictIds may hold at most 30 districts.");
    }
    const serviceDistrictIds = [
      ...new Set(
        rawDistricts
          .filter((d): d is string => typeof d === "string")
          .map((d) => slugifyAddressComponent(d))
          .filter((d) => d.length > 0),
      ),
    ];
    if (type === "pool" && serviceDistrictIds.length === 0) {
      throw new HttpsError("invalid-argument", "An external courier needs at least one service district.");
    }
    const authUidInput =
      data.authUid === undefined
        ? undefined
        : typeof data.authUid === "string" && data.authUid.trim().length > 0
          ? data.authUid.trim()
          : null;

    const db = getFirestore();
    const branchDoc = await db.collection("branches").doc(branchId).get();
    if (!branchDoc.exists) {
      throw new HttpsError("not-found", "Branch not found.");
    }
    if (branchDoc.data()!.organizationId !== organizationId) {
      // Cross-tenant fails closed as not-found — mirrors
      // `updateBranchOperatingHours.ts`'s own precedent.
      throw new HttpsError("not-found", "Branch not found.");
    }

    const courierRef = courierId
      ? db.collection("couriers").doc(courierId)
      : db.collection("couriers").doc();

    // Faz 3a — editing an existing external courier (e.g. turning it back
    // into a restaurant courier) is manager-and-above too.
    if (type !== "pool" && courierId) {
      const current = await courierRef.get();
      if (current.exists && current.data()!.type === "pool") {
        await requireStaffPermission(request, organizationId, "manageBranch");
      }
    }

    return db.runTransaction(async (tx) => {
      const existing = await tx.get(courierRef);
      const previousAuthUid = existing.exists ? ((existing.data()!.authUid as string | undefined) ?? null) : null;
      const authUid = authUidInput === undefined ? previousAuthUid : authUidInput;
      if (authUid) {
        const accountSnap = await tx.get(db.collection(COURIER_ACCOUNTS_COLLECTION).doc(authUid));
        if (accountSnap.exists && accountSnap.data()!.courierId !== courierRef.id) {
          throw new HttpsError("already-exists", "This account is already linked to another courier.");
        }
      }
      const now = Timestamp.now();
      const revision = existing.exists ? (Number(existing.data()!.revision ?? 1) + 1) : 1;

      tx.set(courierRef, {
        organizationId,
        branchId,
        displayName,
        phoneNumber,
        type,
        vehicleType,
        vehicleIdentifier,
        capacity,
        status,
        dispatchStatus,
        returnedAt: existing.exists ? (existing.data()!.returnedAt ?? null) : null,
        activeOrderIds: existing.exists ? (existing.data()!.activeOrderIds ?? []) : [],
        registeredAt: existing.exists ? existing.data()!.registeredAt : now,
        serviceDistrictIds: type === "pool" ? serviceDistrictIds : [],
        authUid,
        updatedAt: now,
        revision,
      });
      if (previousAuthUid && previousAuthUid !== authUid) {
        tx.delete(db.collection(COURIER_ACCOUNTS_COLLECTION).doc(previousAuthUid));
      }
      if (authUid) {
        tx.set(db.collection(COURIER_ACCOUNTS_COLLECTION).doc(authUid), {
          organizationId,
          courierId: courierRef.id,
          type,
          serviceDistrictIds: type === "pool" ? serviceDistrictIds : [],
          status,
          updatedAt: now,
        });
      }

      return { courierId: courierRef.id, revision };
    });
  },
);
