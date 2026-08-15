import * as logger from "firebase-functions/logger";

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

function isEmulatorContext(): boolean {
  return Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FUNCTIONS_EMULATOR);
}

const emulatorSafeReverseGeocode: ReverseGeocodeFn = async (_apiKey, latitude, longitude) => {
  logger.info(
    `[googleGeocodingClient] emulator/local context — not calling real Geocoding API ` +
      `(lat=${latitude}, lng=${longitude}).`,
  );
  // Deterministic, offline: any point resolves to the same
  // "emulator-fixture-besiktas" fixture `googlePlacesClient.ts` already
  // defines, EXCEPT a specific sentinel point used by tests to exercise
  // the "unresolvable" path.
  if (latitude === 0 && longitude === 0) return null;
  return "emulator-fixture-besiktas";
};

export function defaultReverseGeocodeFn(): ReverseGeocodeFn {
  return isEmulatorContext() ? emulatorSafeReverseGeocode : realReverseGeocode;
}
