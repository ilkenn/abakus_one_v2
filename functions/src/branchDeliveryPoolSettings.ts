import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { DELIVERY_SERVICE_AREAS_COLLECTION, slugifyAddressComponent } from "./deliveryServiceAreas";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";

/**
 * 2026-11-12 (Faz 3b) — the branch's delivery-pool region settings, so the
 * pool works without manual database edits: the branch's default district
 * (`branches.defaultDeliveryDistrictId`, the last fallback of
 * `resolvePoolDistrictId` in `courierPool.ts`) and the districts its
 * enabled service areas cover (offered as choices on the POS).
 */

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return raw.trim();
}

async function loadBranch(organizationId: string, branchId: string) {
  const ref = getFirestore().collection("branches").doc(branchId);
  const snap = await ref.get();
  if (!snap.exists || snap.data()!.organizationId !== organizationId) {
    throw new HttpsError("not-found", "Branch not found.");
  }
  return { ref, data: snap.data()! };
}

export const getBranchPoolSettings = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const branchId = requireString(data.branchId, "branchId");
  await requireStaffPermission(request, organizationId, "manageCourierDispatch");
  await requireBranchAccess(request, organizationId, branchId);
  const branch = await loadBranch(organizationId, branchId);
  const areas = await getFirestore()
    .collection(DELIVERY_SERVICE_AREAS_COLLECTION)
    .where("branchId", "==", branchId)
    .where("enabled", "==", true)
    .get();
  const serviceDistrictIds = [
    ...new Set(
      areas.docs
        .filter((d) => d.data().organizationId === organizationId)
        .map((d) => String(d.data().districtId ?? ""))
        .filter((d) => d.length > 0),
    ),
  ].sort();
  return {
    branchId,
    defaultDeliveryDistrictId: (branch.data.defaultDeliveryDistrictId as string | undefined) ?? null,
    serviceDistrictIds,
  };
});

/** Manager-and-above (`manageBranch`). An empty `districtId` clears it. */
export const setBranchDefaultDeliveryDistrict = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const branchId = requireString(data.branchId, "branchId");
  const raw = typeof data.districtId === "string" ? data.districtId : "";
  const districtId = raw.trim().length === 0 ? null : slugifyAddressComponent(raw);
  if (raw.trim().length > 0 && !districtId) {
    throw new HttpsError("invalid-argument", "districtId is not a valid district name.");
  }
  await requireStaffPermission(request, organizationId, "manageBranch");
  await requireBranchAccess(request, organizationId, branchId);
  const db = getFirestore();
  const uid = request.auth.uid;
  return db.runTransaction(async (tx) => {
    const ref = db.collection("branches").doc(branchId);
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data()!.organizationId !== organizationId) {
      throw new HttpsError("not-found", "Branch not found.");
    }
    const previous = (snap.data()!.defaultDeliveryDistrictId as string | undefined) ?? null;
    const now = Timestamp.now();
    tx.update(ref, { defaultDeliveryDistrictId: districtId, updatedAt: now });
    const roles = (request.auth!.token.roles as Record<string, unknown> | undefined)?.[organizationId];
    writeAuditEvent({
      tx, db, eventId: `branch-${branchId}-defaultDeliveryDistrict-${now.toMillis()}`, organizationId, branchId,
      type: "branch.defaultDeliveryDistrictChanged", targetRef: ref.path,
      previousValue: { defaultDeliveryDistrictId: previous }, newValue: { defaultDeliveryDistrictId: districtId },
      actorType: "staff", actorUid: uid, actorRoles: Array.isArray(roles) ? (roles as string[]) : null,
      correlationId: generateCorrelationId(), now,
    });
    return { branchId, defaultDeliveryDistrictId: districtId };
  });
});
