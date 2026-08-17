import * as logger from "firebase-functions/logger";
import { distanceMeters } from "./fraud/geoDistance";
import { resolveGoogleMapsProviderMode } from "./googleMapsProviderMode";

/**
 * Faz P.2.1 §2 — "if moved coordinates require reverse resolution: server
 * must re-resolve/re-verify before SavedAddress becomes verified." Reverse
 * geocoding (lat/lng -> a real place) is a genuinely separate Google
 * product (Geocoding API) from Places API (New) — P.2's own instruction
 * ("Geocoding only where genuinely required") flagged this as the one
 * case that would need it. Mirrors `googlePlacesClient.ts`'s exact DI/
 * emulator-fake pattern.
 *
 * **Setup note, disclosed**: `GOOGLE_PLACES_SERVER_KEY` was originally
 * restricted (Faz P.2) to Places API (New) only. Reverse geocoding calls
 * the classic Geocoding API, a different product — the same secret is
 * reused here (one server-side credential, one trust boundary, per Faz
 * P.2.1 §3's "do not use the Places key for Maps SDK" instruction, which
 * is about the *client-side rendering* key specifically, not this
 * server-side call), but its Google Cloud Console API restrictions must
 * be widened to also allow "Geocoding API" before this works against the
 * real API — a real, disclosed infrastructure step, not silently assumed
 * to already be in place.
 */

export type ReverseGeocodeFn = (
  apiKey: string,
  latitude: number,
  longitude: number,
) => Promise<string | null>;

export async function realReverseGeocode(
  apiKey: string,
  latitude: number,
  longitude: number,
): Promise<string | null> {
  const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
  url.searchParams.set("latlng", `${latitude},${longitude}`);
  url.searchParams.set("key", apiKey);
  const res = await fetch(url);
  if (!res.ok) {
    logger.warn(`[googleGeocodingClient] reverse geocode HTTP ${res.status}`);
    return null;
  }
  const json = (await res.json()) as {
    status?: string;
    results?: { place_id?: string }[];
  };
  if (json.status !== "OK") return null;
  const placeId = json.results?.[0]?.place_id;
  return placeId ?? null;
}

/**
 * Root cause of the Paket Servis P.3 physical-device "address stuck on one
 * location" report (`docs/decisions.md` Paket Servis P.3 §D13): this
 * function previously collapsed **every** non-`(0,0)` coordinate to the
 * exact same `"emulator-fixture-besiktas"` placeId, regardless of distance
 * — safe and correct for automated emulator-backed tests (which never
 * cared what real address a given test coordinate resolved to, only that
 * it resolved to *something* stable), but indistinguishable, from a
 * physical device manually testing against the local Functions emulator,
 * from a genuine "the server always returns the same address" bug: dragging
 * the map to a materially different point still produced the identical
 * `reverseGeocodeAddressPoint` response every time.
 *
 * **Fix — coordinate-aware, still fully deterministic and offline**: a
 * point within [_NEARBY_THRESHOLD_METERS] of the existing Beşiktaş fixture
 * anchor resolves to that fixture; anything farther resolves to a second,
 * genuinely different fixture (`googlePlacesClient.ts`'s
 * `emulator-fixture-kadikoy`, ~6km away) — proving two materially distant
 * points now produce independent results, exactly what a developer
 * manually dragging the map on a physical device against the emulator
 * needs to see. The threshold (2km) is deliberately smaller than the
 * Beşiktaş↔Kadıköy fixture distance (~6km) so the two fixtures can never
 * both fall on the same side of it, and comfortably larger than every
 * existing test's device-location coordinate distance from the anchor
 * (the closest, `(41.05, 29.01)`, is ~0.6km away — the only other
 * non-sentinel coordinate already in use, ~8km east, is a *raw haversine
 * distance* test that never asserts which fixture/district was resolved,
 * so it is unaffected either way).
 */
const BESIKTAS_FIXTURE_ANCHOR = { latitude: 41.0449616, longitude: 29.0076831 };
const _NEARBY_THRESHOLD_METERS = 2000;

const emulatorSafeReverseGeocode: ReverseGeocodeFn = async (_apiKey, latitude, longitude) => {
  logger.info(
    `[googleGeocodingClient] emulator/local context — not calling real Geocoding API ` +
      `(lat=${latitude}, lng=${longitude}).`,
  );
  // Deterministic, offline. A specific sentinel point remains the
  // "unresolvable" path, tested explicitly.
  if (latitude === 0 && longitude === 0) return null;
  const distanceFromBesiktasAnchor = distanceMeters(
    BESIKTAS_FIXTURE_ANCHOR.latitude,
    BESIKTAS_FIXTURE_ANCHOR.longitude,
    latitude,
    longitude,
  );
  return distanceFromBesiktasAnchor <= _NEARBY_THRESHOLD_METERS
    ? "emulator-fixture-besiktas"
    : "emulator-fixture-kadikoy";
};

export function defaultReverseGeocodeFn(): ReverseGeocodeFn {
  return resolveGoogleMapsProviderMode() === "fixture" ? emulatorSafeReverseGeocode : realReverseGeocode;
}
