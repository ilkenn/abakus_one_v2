/**
 * Pure, network-free normalization of a raw Google Places API (New) Place
 * Details response into this app's own provider-neutral address shape —
 * Faz P.2. Field mapping is evidence-based, not assumed from Google's
 * generic documentation: a real coverage spike against Istanbul addresses
 * (Beşiktaş/Şişli/Beyoğlu/Kağıthane/Sarıyer/Maslak/Okmeydanı, `docs/decisions.md`
 * Faz P.2) found that Turkish addresses do **not** populate the
 * `sublocality_level_1`/`sublocality` types Google's docs emphasize for
 * neighborhood-level data — mahalle (neighborhood) instead appears under
 * `administrative_area_level_4`. This module encodes that finding directly
 * rather than a generic/assumed mapping.
 *
 * No production module calls the real Google API from inside this file —
 * see `googlePlacesClient.ts` for the actual HTTP client. Kept separate so
 * this mapping logic is testable with zero network/emulator dependency,
 * against realistic fixtures captured from the real spike.
 */

export interface RawAddressComponent {
  longText?: string;
  shortText?: string;
  types?: string[];
}

export interface RawPlaceDetails {
  id?: string;
  formattedAddress?: string;
  addressComponents?: RawAddressComponent[];
  location?: { latitude?: number; longitude?: number };
}

export interface NormalizedAddress {
  providerPlaceId: string;
  formattedAddress: string | null;
  provinceName: string | null;
  districtName: string | null;
  neighborhoodName: string | null;
  routeName: string | null;
  streetNumber: string | null;
  latitude: number | null;
  longitude: number | null;
}

export function extractComponent(
  components: RawAddressComponent[] | undefined,
  types: string[],
): RawAddressComponent | null {
  if (!Array.isArray(components)) return null;
  const match = components.find(
    (c) => Array.isArray(c.types) && c.types.some((t) => types.includes(t)),
  );
  return match ?? null;
}

/**
 * `placeId` is passed in separately (not read off `raw.id`) since the
 * caller always already knows which place it requested — defensive
 * against a malformed/missing `id` field in the raw response.
 */
export function normalizePlaceDetails(
  placeId: string,
  raw: RawPlaceDetails,
): NormalizedAddress {
  const components = raw.addressComponents;
  const province = extractComponent(components, ["administrative_area_level_1"]);
  const district = extractComponent(components, ["administrative_area_level_2"]);
  // Faz P.2 spike finding — mahalle (neighborhood) is administrative_area_level_4
  // for Turkish addresses, not the sublocality_* types.
  const neighborhood = extractComponent(components, ["administrative_area_level_4"]);
  const route = extractComponent(components, ["route"]);
  const streetNumber = extractComponent(components, ["street_number"]);

  return {
    providerPlaceId: placeId,
    formattedAddress: raw.formattedAddress ?? null,
    provinceName: province?.longText ?? null,
    districtName: district?.longText ?? null,
    neighborhoodName: neighborhood?.longText ?? null,
    routeName: route?.longText ?? null,
    streetNumber: streetNumber?.longText ?? null,
    latitude: typeof raw.location?.latitude === "number" ? raw.location.latitude : null,
    longitude: typeof raw.location?.longitude === "number" ? raw.location.longitude : null,
  };
}

/**
 * Faz P.2 §5 — "if provider cannot reliably resolve an address, keep it
 * unverified." Province, district, and coordinates are treated as the
 * minimum bar for a delivery-authorization-eligible verification;
 * neighborhood/route/streetNumber are genuinely optional (the spike found
 * real, legitimate places missing one or more of these — e.g. a
 * mahalle-level query with no street in it has no route/streetNumber by
 * construction, not a provider failure).
 */
export function isSufficientlyResolved(address: NormalizedAddress): boolean {
  return (
    address.provinceName !== null &&
    address.districtName !== null &&
    address.latitude !== null &&
    address.longitude !== null
  );
}
