import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, type DocumentData, type Firestore } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { DELIVERY_SERVICE_AREAS_COLLECTION, slugifyAddressComponent } from "./deliveryServiceAreas";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";

/**
 * 2026-11-12 (Faz 4, ADR-081) — per-neighborhood delivery rules a branch
 * manages itself: "Minimum Sepet Tutarı" and "Tahmini Teslimat Süresi".
 *
 * Stored on the EXISTING `deliveryServiceAreas` records (P.3) rather than a
 * parallel collection: one record per (district, neighborhood) per branch is
 * already the coverage key the customer app's `resolveDeliveryServiceArea`
 * and the pool's region lookup use, and it already carries
 * `minimumOrderMinorUnits`. This module adds `estimatedDeliveryMinutes` and
 * `neighborhoodName` (display label) and the first branch-side editor for
 * them — until now these records were seeded by scripts only.
 *
 * - Reading the branch's zones: `manageDeliveryOrders` (every front-line
 *   role that opens a Paket Servis order needs the minimums to warn).
 * - Writing: `manageBranch` (manager and above), audited.
 * - A (district, neighborhood) pair enabled for ANOTHER branch is refused:
 *   `resolveDeliveryServiceArea` fails closed on two enabled matches
 *   ("ambiguous"), so an edit here must never break the customer app.
 * - A POS staff address is typed by hand and has only a neighborhood name;
 *   [resolveBranchZone] matches it on the neighborhood slug within the
 *   branch, preferring the branch's default district when two districts of
 *   the same branch share a neighborhood name.
 */

export const MAX_MINIMUM_ORDER_MINOR_UNITS = 1_000_000; // 10.000 TL
export const MIN_ESTIMATED_DELIVERY_MINUTES = 5;
export const MAX_ESTIMATED_DELIVERY_MINUTES = 240;

export interface BranchDeliveryZone {
  id: string;
  districtId: string;
  neighborhoodId: string;
  neighborhoodName: string;
  minimumOrderMinorUnits: number;
  estimatedDeliveryMinutes: number | null;
  enabled: boolean;
}

export function parseBranchDeliveryZone(id: string, data: DocumentData): BranchDeliveryZone {
  const eta = data.estimatedDeliveryMinutes;
  return {
    id,
    districtId: String(data.districtId ?? ""),
    neighborhoodId: String(data.neighborhoodId ?? ""),
    neighborhoodName: String(data.neighborhoodName ?? data.neighborhoodId ?? ""),
    minimumOrderMinorUnits: typeof data.minimumOrderMinorUnits === "number" ? data.minimumOrderMinorUnits : 0,
    estimatedDeliveryMinutes: typeof eta === "number" && Number.isInteger(eta) ? eta : null,
    enabled: data.enabled === true,
  };
}

/**
 * The enabled zone of the branch for a hand-typed neighborhood name, or
 * `null` (no rule: the order is not gated — product-owner decision 3 keeps
 * staff orders flexible outside configured neighborhoods). Pure.
 */
export function resolveBranchZone(
  zones: readonly BranchDeliveryZone[],
  neighborhoodName: string,
  defaultDistrictId: string | null,
): BranchDeliveryZone | null {
  const neighborhoodId = slugifyAddressComponent(neighborhoodName);
  if (neighborhoodId.length === 0) return null;
  const matches = zones.filter((z) => z.enabled && z.neighborhoodId === neighborhoodId);
  if (matches.length === 0) return null;
  if (matches.length === 1) return matches[0];
  return matches.find((z) => z.districtId === defaultDistrictId) ?? null;
}

export type MinimumOrderCheck =
  | { status: "noRule" }
  | { status: "met"; minimumOrderMinorUnits: number }
  | { status: "below"; minimumOrderMinorUnits: number; shortfallMinorUnits: number };

/** The basket (products only, delivery fee excluded) against the zone's minimum. Pure. */
export function checkMinimumOrder(zone: BranchDeliveryZone | null, basketMinorUnits: number): MinimumOrderCheck {
  if (!zone || zone.minimumOrderMinorUnits <= 0) return { status: "noRule" };
  if (basketMinorUnits >= zone.minimumOrderMinorUnits) {
    return { status: "met", minimumOrderMinorUnits: zone.minimumOrderMinorUnits };
  }
  return {
    status: "below",
    minimumOrderMinorUnits: zone.minimumOrderMinorUnits,
    shortfallMinorUnits: zone.minimumOrderMinorUnits - basketMinorUnits,
  };
}

/** Every zone record of the branch (enabled and disabled), sorted by neighborhood. */
export async function loadBranchDeliveryZones(
  db: Firestore,
  organizationId: string,
  branchId: string,
): Promise<BranchDeliveryZone[]> {
  const snap = await db.collection(DELIVERY_SERVICE_AREAS_COLLECTION).where("branchId", "==", branchId).get();
  return snap.docs
    .filter((d) => d.data().organizationId === organizationId)
    .map((d) => parseBranchDeliveryZone(d.id, d.data()))
    .sort((a, b) => a.neighborhoodName.localeCompare(b.neighborhoodName, "tr"));
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) invalid(`${field} is required.`);
  return (raw as string).trim();
}

function boundedInt(raw: unknown, field: string, min: number, max: number): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < min || raw > max) {
    invalid(`${field} must be an integer between ${min} and ${max}.`);
  }
  return raw as number;
}

async function loadBranch(db: Firestore, organizationId: string, branchId: string) {
  const snap = await db.collection("branches").doc(branchId).get();
  if (!snap.exists || snap.data()!.organizationId !== organizationId) {
    throw new HttpsError("not-found", "Branch not found.");
  }
  return snap.data()!;
}

async function authorizeBranch(request: CallableRequest, permission: "manageDeliveryOrders" | "manageBranch") {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const branchId = requireString(data.branchId, "branchId");
  await requireStaffPermission(request, organizationId, permission);
  await requireBranchAccess(request, organizationId, branchId);
  return { data, organizationId, branchId, uid: request.auth.uid };
}

export const listBranchDeliveryZones = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  const { organizationId, branchId } = await authorizeBranch(request, "manageDeliveryOrders");
  const db = getFirestore();
  const branch = await loadBranch(db, organizationId, branchId);
  const zones = await loadBranchDeliveryZones(db, organizationId, branchId);
  return {
    branchId,
    defaultDeliveryDistrictId: (branch.defaultDeliveryDistrictId as string | undefined) ?? null,
    zones,
  };
});

/**
 * Creates or edits one neighborhood rule of the branch. The district comes
 * from `districtName` when given, else the branch's default district (Faz
 * 3b "Varsayılan İlçe"); one of the two is required. Re-saving an existing
 * (district, neighborhood) pair of the branch edits that record.
 */
export const upsertBranchDeliveryZone = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  const { data, organizationId, branchId, uid } = await authorizeBranch(request, "manageBranch");
  const neighborhoodName = requireString(data.neighborhoodName, "neighborhoodName");
  if (neighborhoodName.length > 80) invalid("neighborhoodName must be at most 80 characters.");
  const neighborhoodId = slugifyAddressComponent(neighborhoodName);
  if (neighborhoodId.length === 0) invalid("neighborhoodName is not a valid neighborhood name.");
  const minimumOrderMinorUnits = boundedInt(data.minimumOrderMinorUnits, "minimumOrderMinorUnits", 0, MAX_MINIMUM_ORDER_MINOR_UNITS);
  const estimatedDeliveryMinutes = data.estimatedDeliveryMinutes === null || data.estimatedDeliveryMinutes === undefined
    ? null
    : boundedInt(data.estimatedDeliveryMinutes, "estimatedDeliveryMinutes", MIN_ESTIMATED_DELIVERY_MINUTES, MAX_ESTIMATED_DELIVERY_MINUTES);
  const enabled = data.enabled === undefined ? true : data.enabled === true;

  const db = getFirestore();
  const branch = await loadBranch(db, organizationId, branchId);
  const districtRaw = typeof data.districtName === "string" ? data.districtName.trim() : "";
  const districtId = districtRaw.length > 0
    ? slugifyAddressComponent(districtRaw)
    : ((branch.defaultDeliveryDistrictId as string | undefined) ?? "");
  if (districtId.length === 0) {
    throw new HttpsError("failed-precondition", "Set the branch's default district or give a district name.", {
      code: "deliveryZone/district-required",
    });
  }

  return db.runTransaction(async (tx) => {
    const samePair = await tx.get(
      db.collection(DELIVERY_SERVICE_AREAS_COLLECTION)
        .where("districtId", "==", districtId)
        .where("neighborhoodId", "==", neighborhoodId),
    );
    const own = samePair.docs.filter((d) => d.data().branchId === branchId && d.data().organizationId === organizationId);
    const others = samePair.docs.filter((d) => !(d.data().branchId === branchId && d.data().organizationId === organizationId));
    if (enabled && others.some((d) => d.data().enabled === true)) {
      throw new HttpsError("failed-precondition", "This neighborhood is already served by another branch.", {
        code: "deliveryZone/covered-by-other-branch",
      });
    }
    const ref = own.length > 0
      ? own[0].ref
      : db.collection(DELIVERY_SERVICE_AREAS_COLLECTION).doc(`zone_${branchId}_${districtId}_${neighborhoodId}`);
    const previous = own.length > 0 ? parseBranchDeliveryZone(own[0].id, own[0].data()) : null;
    const now = Timestamp.now();
    tx.set(ref, {
      organizationId,
      branchId,
      restaurantId: (branch.restaurantId as string | undefined) ?? "",
      districtId,
      neighborhoodId,
      neighborhoodName,
      enabled,
      minimumOrderMinorUnits,
      estimatedDeliveryMinutes,
      updatedAt: now,
      updatedByUid: uid,
      ...(previous ? {} : { createdAt: now }),
    }, { merge: true });
    // Duplicates of the same pair within the branch (a seeding defect) are
    // disabled so the pair resolves to exactly one record.
    for (const extra of own.slice(1)) {
      if (extra.data().enabled === true) tx.update(extra.ref, { enabled: false, updatedAt: now, updatedByUid: uid });
    }
    const zone: BranchDeliveryZone = {
      id: ref.id, districtId, neighborhoodId, neighborhoodName, minimumOrderMinorUnits, estimatedDeliveryMinutes, enabled,
    };
    const roles = (request.auth!.token.roles as Record<string, unknown> | undefined)?.[organizationId];
    writeAuditEvent({
      tx, db, eventId: `deliveryZone-${ref.id}-${now.toMillis()}`, organizationId, branchId,
      type: previous ? "deliveryZone.updated" : "deliveryZone.created", targetRef: ref.path,
      previousValue: previous ? { ...previous } : null, newValue: { ...zone },
      actorType: "staff", actorUid: uid, actorRoles: Array.isArray(roles) ? (roles as string[]) : null,
      correlationId: generateCorrelationId(), now,
    });
    return { zone };
  });
});
