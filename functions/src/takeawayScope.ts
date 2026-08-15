import type { Firestore } from "firebase-admin/firestore";

/**
 * Shared "is this organization/restaurant/branch a valid, currently-usable
 * takeaway scope" logic — Faz D.3 (Server-Authoritative Pricing + Takeaway
 * Order Creation). Extracted out of `takeawayQrTokenResolution.ts` (Faz
 * D.2) so `submitTakeawayOrder`'s authenticated-customer branch (which has
 * no QR token to resolve, only a client-supplied `restaurantId`/
 * `branchId`) validates against the exact same canonical chain rules as
 * QR resolution does, rather than a second, independently-drifting copy —
 * per this phase's own explicit "Duplicate business logic oluşturma"
 * instruction.
 *
 * `resolveTakeawayQrTokenInternal` now calls [resolveActiveTakeawayBranch]
 * itself (refactor, not a behavior change — its own emulator test suite,
 * unmodified, re-verifies this).
 */

export type TakeawayScopeStatus = "valid" | "invalid" | "notFound";

export interface TakeawayScopeResolution {
  status: TakeawayScopeStatus;
  organizationId?: string;
  restaurantId?: string;
  branchId?: string;
  branchDisplayName?: string;
}

export function isOrganizationActive(data: FirebaseFirestore.DocumentData): boolean {
  return data.isActive === true;
}

export function isRestaurantActive(data: FirebaseFirestore.DocumentData): boolean {
  return data.isActive === true;
}

/** `status == 'active'`, not `emergencyStopped`, and `'takeaway' in supportedOrderChannelIds` — the three branch-level conditions `resolveTakeawayQrTokenInternal`'s own doc comment (step 8) already specifies. */
export function isBranchTakeawayReady(data: FirebaseFirestore.DocumentData): boolean {
  if (data.status !== "active") return false;
  if (data.emergencyStopped === true) return false;
  const supportedChannels: unknown = data.supportedOrderChannelIds;
  return Array.isArray(supportedChannels) && supportedChannels.includes("takeaway");
}

/**
 * Resolves and validates a `restaurantId`/`branchId` pair against the real
 * `organizations`/`restaurants`/`branches` canonical chain (Faz D.1/D.1.1).
 *
 * [expectedOrganizationId], when given, additionally requires the
 * *restaurant's own* `organizationId` to match it exactly — the QR case,
 * where a `takeawayQrCodes` document independently claims an
 * `organizationId` that must be cross-checked against the real chain
 * (Faz D.2's "cross-tenant binding mismatch" scenario). Omitted for the
 * authenticated-customer case, which has no separate claim to cross-check
 * — `organizationId` is derived entirely from the resolved restaurant
 * document itself, never a second client input.
 *
 * `notFound` for a broken/nonexistent/mismatched chain link; `invalid`
 * for a chain that's intact but not currently operational (inactive
 * organization/restaurant, non-active/emergency-stopped/takeaway-
 * unsupported branch) — mirrors `resolveTakeawayQrTokenInternal`'s own
 * status-split convention exactly (unchanged by this refactor).
 */
export async function resolveActiveTakeawayBranch(
  db: Firestore,
  params: { restaurantId: string; branchId: string; expectedOrganizationId?: string },
): Promise<TakeawayScopeResolution> {
  const { restaurantId, branchId, expectedOrganizationId } = params;

  const restaurantDoc = await db.collection("restaurants").doc(restaurantId).get();
  if (!restaurantDoc.exists) {
    return { status: "notFound" };
  }
  const restaurant = restaurantDoc.data()!;
  const organizationId = restaurant.organizationId;
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    return { status: "notFound" };
  }
  if (expectedOrganizationId !== undefined && organizationId !== expectedOrganizationId) {
    return { status: "notFound" };
  }

  const organizationDoc = await db.collection("organizations").doc(organizationId).get();
  if (!organizationDoc.exists) {
    return { status: "notFound" };
  }
  if (!isOrganizationActive(organizationDoc.data()!)) {
    return { status: "invalid" };
  }
  if (!isRestaurantActive(restaurant)) {
    return { status: "invalid" };
  }

  const branchDoc = await db.collection("branches").doc(branchId).get();
  if (!branchDoc.exists) {
    return { status: "notFound" };
  }
  const branch = branchDoc.data()!;
  if (branch.restaurantId !== restaurantId || branch.organizationId !== organizationId) {
    return { status: "notFound" };
  }
  if (!isBranchTakeawayReady(branch)) {
    return { status: "invalid" };
  }

  return {
    status: "valid",
    organizationId,
    restaurantId,
    branchId,
    branchDisplayName: typeof branch.name === "string" ? branch.name : undefined,
  };
}
