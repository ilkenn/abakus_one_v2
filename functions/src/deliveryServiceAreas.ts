import type { Firestore, Transaction } from "firebase-admin/firestore";

/**
 * Server-authoritative delivery service-area (coverage/minimum-order)
 * domain — Paket Servis P.3. No such domain existed anywhere in this
 * codebase before this phase (confirmed by a real search of both `lib/`
 * and `functions/src/` — the only prior concept was a legacy, mock,
 * client-only `DeliveryZoneModel`). This is the foundation only, per
 * explicit instruction: no production neighborhood coverage or minimum-
 * order amounts are seeded here — only dev/test fixtures, seeded by
 * scripts/tests themselves.
 *
 * **Canonical identity, not operational labels.** Keyed on the exact same
 * `districtId`/`neighborhoodId` slug convention `SavedAddress` already
 * derives from Google Places results (`slugifyAddressComponent`, ported
 * here byte-for-byte from `saved_address_repository.dart`'s Dart original
 * — same "no Dart<->TypeScript sharing mechanism" duplication precedent as
 * every other mirrored file). Operational-region labels (e.g. "Okmeydanı",
 * "Maslak" — colloquial groupings spanning several real mahalles, per the
 * Faz P.2 coverage spike's own finding) are deliberately NOT part of this
 * matching key at all — they must never masquerade as canonical postal
 * hierarchy, so this module simply has no concept of them.
 *
 * **Fail-closed by construction**: zero matches -> not deliverable.
 * More than one enabled match for the same (districtId, neighborhoodId)
 * pair -> `ambiguous`, treated as NOT deliverable (a configuration defect,
 * never resolved by picking one arbitrarily). There is no "assume all of
 * Istanbul is covered" fallback anywhere in this module.
 */

/** Ported byte-for-byte from `lib/features/orders/data/saved_address_repository.dart`'s `slugifyAddressComponent` — must stay in sync by hand. */
export function slugifyAddressComponent(input: string): string {
  const replacements: Record<string, string> = {
    ç: "c",
    Ç: "c",
    ğ: "g",
    Ğ: "g",
    ı: "i",
    I: "i",
    İ: "i",
    i: "i",
    ö: "o",
    Ö: "o",
    ş: "s",
    Ş: "s",
    ü: "u",
    Ü: "u",
  };
  let result = input.toLowerCase();
  for (const [from, to] of Object.entries(replacements)) {
    result = result.split(from.toLowerCase()).join(to);
  }
  result = result.trim().replace(/\s+/g, "_");
  result = result.replace(/[^a-z0-9_]/g, "");
  return result;
}

export interface DeliveryServiceArea {
  id: string;
  organizationId: string;
  branchId: string;
  restaurantId: string;
  districtId: string;
  neighborhoodId: string;
  enabled: boolean;
  minimumOrderMinorUnits: number;
}

export type DeliveryEligibilityResult =
  | { status: "eligible"; area: DeliveryServiceArea }
  | { status: "notCovered" }
  | { status: "ambiguous" };

export const DELIVERY_SERVICE_AREAS_COLLECTION = "deliveryServiceAreas";

function parseServiceArea(id: string, data: FirebaseFirestore.DocumentData): DeliveryServiceArea {
  return {
    id,
    organizationId: String(data.organizationId ?? ""),
    branchId: String(data.branchId ?? ""),
    restaurantId: String(data.restaurantId ?? ""),
    districtId: String(data.districtId ?? ""),
    neighborhoodId: String(data.neighborhoodId ?? ""),
    enabled: data.enabled === true,
    minimumOrderMinorUnits:
      typeof data.minimumOrderMinorUnits === "number" ? data.minimumOrderMinorUnits : 0,
  };
}

/**
 * Equality-only query (districtId + neighborhoodId + enabled) —
 * deliberately no `orderBy`, so this never requires a Firestore composite
 * index. Zero results -> `notCovered`. More than one result -> `ambiguous`
 * (fail closed — never picks the first one arbitrarily; this would only
 * happen from a real configuration defect, since a well-formed dataset has
 * at most one enabled record per district+neighborhood pair).
 */
export async function resolveDeliveryServiceArea(
  db: Firestore,
  params: { districtId: string; neighborhoodId: string },
  tx?: Transaction,
): Promise<DeliveryEligibilityResult> {
  const query = db
    .collection(DELIVERY_SERVICE_AREAS_COLLECTION)
    .where("districtId", "==", params.districtId)
    .where("neighborhoodId", "==", params.neighborhoodId)
    .where("enabled", "==", true);
  const snapshot = tx ? await tx.get(query) : await query.get();
  if (snapshot.empty) return { status: "notCovered" };
  if (snapshot.docs.length > 1) return { status: "ambiguous" };
  return { status: "eligible", area: parseServiceArea(snapshot.docs[0].id, snapshot.docs[0].data()) };
}
