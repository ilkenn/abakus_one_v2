import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
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
    // 2026-11-12 — a NEW courier starts "available": staff add a courier
    // because it is at the shop, and "Kurye Ata" lists available couriers
    // only (it started "offline" and never appeared there). An edit keeps
    // the current value unless one is sent (see `keep` below).
    const dispatchStatus = optionalEnum(
      data.dispatchStatus,
      VALID_DISPATCH_STATUSES,
      "dispatchStatus",
      "available",
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
    let authUidInput =
      data.authUid === undefined
        ? undefined
        : typeof data.authUid === "string" && data.authUid.trim().length > 0
          ? data.authUid.trim()
          : null;
    // 2026-11-12 (Faz 3b) — linking the courier's sign-in by the e-mail of
    // its staff account ("" or null = unlink). The account must hold an
    // active `courier` membership in this organization. Changing the link
    // at all is manager-and-above (`manageBranch`).
    let authEmail: string | null | undefined = undefined;
    if (data.authEmail !== undefined) {
      const raw = typeof data.authEmail === "string" ? data.authEmail.trim().toLowerCase() : "";
      if (raw.length === 0) {
        authUidInput = null;
        authEmail = null;
      } else {
        let uid: string;
        try {
          uid = (await getAuth().getUserByEmail(raw)).uid;
        } catch {
          throw new HttpsError("not-found", "No sign-in account exists for this e-mail.", {
            code: "courier/account-not-found",
          });
        }
        const membership = await getFirestore().collection("memberships").doc(`${organizationId}_${uid}`).get();
        const roles: unknown = membership.data()?.roles;
        if (
          !membership.exists ||
          membership.data()!.status !== "active" ||
          !Array.isArray(roles) ||
          !roles.includes("courier")
        ) {
          throw new HttpsError("failed-precondition", "This account is not an active courier of this organization.", {
            code: "courier/account-not-courier",
          });
        }
        authUidInput = uid;
        authEmail = raw;
      }
    }
    if (authUidInput !== undefined) {
      await requireStaffPermission(request, organizationId, "manageBranch");
    }

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
      const previousAuthEmail = existing.exists ? ((existing.data()!.authEmail as string | undefined) ?? null) : null;
      const storedAuthEmail = authEmail !== undefined ? authEmail : authUid === previousAuthUid ? previousAuthEmail : null;
      // Faz 3b — an edit keeps the operational fields the caller did not
      // send (before, an edit silently reset dispatchStatus to "offline").
      const prior = existing.exists ? existing.data()! : {};
      const keep = <T>(field: string, sent: unknown, value: T): T =>
        sent === undefined && existing.exists && prior[field] !== undefined ? (prior[field] as T) : value;
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
        vehicleType: keep("vehicleType", data.vehicleType, vehicleType),
        vehicleIdentifier: keep("vehicleIdentifier", data.vehicleIdentifier, vehicleIdentifier),
        capacity: keep("capacity", data.capacity, capacity),
        status: keep("status", data.status, status),
        dispatchStatus: keep("dispatchStatus", data.dispatchStatus, dispatchStatus),
        returnedAt: existing.exists ? (existing.data()!.returnedAt ?? null) : null,
        activeOrderIds: existing.exists ? (existing.data()!.activeOrderIds ?? []) : [],
        registeredAt: existing.exists ? existing.data()!.registeredAt : now,
        serviceDistrictIds: type === "pool" ? serviceDistrictIds : [],
        authUid,
        authEmail: storedAuthEmail,
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
          displayName,
          type,
          serviceDistrictIds: type === "pool" ? serviceDistrictIds : [],
          status: keep("status", data.status, status),
          updatedAt: now,
        });
      }

      return { courierId: courierRef.id, revision };
    });
  },
);
