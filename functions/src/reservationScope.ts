import type { Firestore, Transaction } from "firebase-admin/firestore";
import { loadReservationPolicy, type ReservationPolicy } from "./reservationConfig";

/**
 * Reservation scope/area resolution — Faz R.1A. Hand-mirrors
 * `takeawayScope.ts`'s `resolveActiveTakeawayBranch` shape exactly (same
 * `organizations` -> `restaurants` -> `branches` canonical-chain
 * validation, same `notFound`/`invalid` status split), with one deliberate
 * difference the Faz R.0.5/R.0.6 correction requires: capability is decided
 * by `ReservationPolicy.enabled`, never by `branch.supportedOrderChannelIds`
 * — see `reservationConfig.ts`'s own doc comment on `ReservationPolicy
 * .enabled` for why that axis is wrong for this domain.
 *
 * **Faz R.1A.1 REQUIRED fix #1 — transaction-consistent reads.** Every
 * document this module reads (`restaurants`/`organizations`/`branches`/
 * `reservationPolicies`/`reservationAreas`) is now read via `tx.get()`,
 * never a plain `.get()`. All of it is authoritative input to the accept/
 * reject decision `submitReservation`'s transaction makes — a plain read
 * doesn't participate in Firestore's optimistic-concurrency conflict
 * detection, so a write landing on any of these documents while the
 * transaction is in flight would previously go undetected, letting the
 * transaction commit against stale scope/policy/area state instead of
 * being forced to retry and re-read. Both functions now **require** a
 * `Transaction` parameter — a caller can no longer accidentally reintroduce
 * a plain, non-transactional read path for this data.
 */

export type ReservationScopeStatus = "valid" | "invalid" | "notFound";

export interface ReservationScopeResolution {
  status: ReservationScopeStatus;
  organizationId?: string;
  restaurantId?: string;
  branchId?: string;
  policy?: ReservationPolicy;
}

export async function resolveActiveReservationBranch(
  tx: Transaction,
  db: Firestore,
  params: { restaurantId: string; branchId: string },
): Promise<ReservationScopeResolution> {
  const { restaurantId, branchId } = params;

  const restaurantDoc = await tx.get(db.collection("restaurants").doc(restaurantId));
  if (!restaurantDoc.exists) {
    return { status: "notFound" };
  }
  const restaurant = restaurantDoc.data()!;
  const organizationId = restaurant.organizationId;
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    return { status: "notFound" };
  }

  const organizationDoc = await tx.get(db.collection("organizations").doc(organizationId));
  if (!organizationDoc.exists) {
    return { status: "notFound" };
  }
  if (organizationDoc.data()!.isActive !== true) {
    return { status: "invalid" };
  }
  if (restaurant.isActive !== true) {
    return { status: "invalid" };
  }

  const branchDoc = await tx.get(db.collection("branches").doc(branchId));
  if (!branchDoc.exists) {
    return { status: "notFound" };
  }
  const branch = branchDoc.data()!;
  if (branch.restaurantId !== restaurantId || branch.organizationId !== organizationId) {
    return { status: "notFound" };
  }
  if (branch.status !== "active" || branch.emergencyStopped === true) {
    return { status: "invalid" };
  }

  const policy = await loadReservationPolicy(tx, db, branchId);
  if (!policy || policy.enabled !== true) {
    return { status: "invalid" };
  }

  return { status: "valid", organizationId, restaurantId, branchId, policy };
}

export type ReservationAreaStatus = "valid" | "invalid" | "notFound";

export interface ReservationAreaResolution {
  status: ReservationAreaStatus;
  areaId?: string;
  displayName?: string;
  capacity?: number;
}

/**
 * Validates a client-claimed `areaId` actually belongs to `branchId` (the
 * one, already tenant-verified by `resolveActiveReservationBranch`,
 * anchor), is active, and carries a usable capacity — mirrors
 * `submitTakeawayOrder.ts`'s `product.restaurantId !== scope.restaurantId`
 * single-hop ownership check: since `branchId` is already tenant-verified
 * by the time this is called, checking `area.branchId == branchId` is
 * sufficient to make the whole chain tenant-safe — a client can never
 * supply another tenant's `areaId` and have it resolve for this branch (Faz
 * R.0.6 §9's "cross-tenant reads/writes must fail closed" requirement).
 */
export async function resolveReservationArea(
  tx: Transaction,
  db: Firestore,
  params: { branchId: string; areaId: string },
): Promise<ReservationAreaResolution> {
  const doc = await tx.get(db.collection("reservationAreas").doc(params.areaId));
  if (!doc.exists) {
    return { status: "notFound" };
  }
  const area = doc.data()!;
  if (area.branchId !== params.branchId) {
    // Deliberately notFound, not invalid — an area belonging to a
    // different branch/tenant must resolve identically to a genuinely
    // unknown areaId, never confirm its existence to a caller probing for
    // other tenants' area ids (mirrors this codebase's own
    // not-found-not-existence-oracle precedent, e.g. processAccountDeletion).
    return { status: "notFound" };
  }
  if (area.isActive !== true) {
    return { status: "invalid" };
  }
  const capacity = Number(area.capacity);
  if (!Number.isFinite(capacity) || capacity <= 0) {
    return { status: "invalid" };
  }
  return { status: "valid", areaId: params.areaId, displayName: area.displayName, capacity };
}
