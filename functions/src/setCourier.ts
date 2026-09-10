import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
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

    requireStaffPermission(request, organizationId, "manageCourierDispatch");

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

    return db.runTransaction(async (tx) => {
      const existing = await tx.get(courierRef);
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
        updatedAt: now,
        revision,
      });

      return { courierId: courierRef.id, revision };
    });
  },
);
