import * as logger from "firebase-functions/logger";
import type { RawPlaceDetails } from "./googlePlacesFieldMapping";

/**
 * The one seam that makes the delivery-address callables testable without
 * real network access or a real Google API key — mirrors
 * `reservationNotificationDelivery.ts`'s `PushSender`/`defaultSender()`
 * pattern exactly (§18 of that file's own doc comment): production wires
 * [defaultAutocompleteFn]/[defaultPlaceDetailsFn], which detect the local
 * emulator and substitute a safe, deterministic fake that never calls
 * Google's real API (and never reads the real secret) — tests call the
 * exported handlers with an explicit fake for full control. No caching of
 * Google data is implemented (Faz P.2 §12 — "do not invent unsupported
 * caching of Google data"); every call is a real request against the
 * live API in production.
 */

export interface AutocompleteSuggestion {
  placeId: string;
  text: string;
}

export type AutocompleteFn = (
  apiKey: string,
  input: string,
  sessionToken: string,
) => Promise<AutocompleteSuggestion[]>;

export type PlaceDetailsFn = (
  apiKey: string,
  placeId: string,
  sessionToken: string,
) => Promise<RawPlaceDetails | null>;

// Faz P.2 §3 — geographic bias toward Istanbul/the operating area, proven
// against real Istanbul samples in the coverage spike.
const ISTANBUL_LOCATION_BIAS = {
  circle: {
    center: { latitude: 41.0082, longitude: 28.9784 },
    radius: 50000.0,
  },
};

/**
 * Extracted as a pure, network-free function so its content (Faz P.2 §3's
 * TR restriction and Istanbul location bias) is directly unit-testable
 * without mocking `fetch`.
 */
export function buildAutocompleteRequestBody(
  input: string,
  sessionToken: string,
): Record<string, unknown> {
  return {
    input,
    sessionToken,
    // Faz P.2 §3 — country restriction, TR only.
    includedRegionCodes: ["tr"],
    languageCode: "tr",
    locationBias: ISTANBUL_LOCATION_BIAS,
  };
}

export async function realAutocomplete(
  apiKey: string,
  input: string,
  sessionToken: string,
): Promise<AutocompleteSuggestion[]> {
  const res = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Goog-Api-Key": apiKey },
    body: JSON.stringify(buildAutocompleteRequestBody(input, sessionToken)),
  });
  if (!res.ok) {
    logger.warn(`[googlePlacesClient] autocomplete HTTP ${res.status}`);
    return [];
  }
  const json = (await res.json()) as {
    suggestions?: { placePrediction?: { placeId?: string; text?: { text?: string } } }[];
  };
  const suggestions = json.suggestions ?? [];
  return suggestions
    .map((s) => ({
      placeId: s.placePrediction?.placeId ?? "",
      text: s.placePrediction?.text?.text ?? "",
    }))
    .filter((s) => s.placeId.length > 0);
}

export async function realPlaceDetails(
  apiKey: string,
  placeId: string,
  sessionToken: string,
): Promise<RawPlaceDetails | null> {
  const fieldMask = ["id", "formattedAddress", "addressComponents", "location"].join(",");
  // sessionToken as a query param ends the Autocomplete session this
  // Details call belongs to — the same session's earlier autocomplete
  // requests are billed as one bundled session rather than pay-per-request
  // (Faz P.2 §12 cost control; Google's own documented session model).
  const url = new URL(`https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`);
  url.searchParams.set("sessionToken", sessionToken);
  const res = await fetch(url, {
    method: "GET",
    headers: { "X-Goog-Api-Key": apiKey, "X-Goog-FieldMask": fieldMask },
  });
  if (!res.ok) {
    logger.warn(`[googlePlacesClient] place details HTTP ${res.status}`);
    return null;
  }
  return (await res.json()) as RawPlaceDetails;
}

function isEmulatorContext(): boolean {
  return Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FUNCTIONS_EMULATOR);
}

/**
 * Deterministic, offline fixture data — never a real network call, never
 * reads a real API key. Shaped from real, evidence-based spike results
 * (`docs/decisions.md` Faz P.2) so emulator-suite tests exercise the same
 * realistic response shape production actually sees, not an invented one.
 */
const EMULATOR_FIXTURE_PLACE_DETAILS: Record<string, RawPlaceDetails> = {
  "emulator-fixture-besiktas": {
    id: "emulator-fixture-besiktas",
    formattedAddress: "Balmumcu, Barbaros Blv. No:74, 34349 Beşiktaş/İstanbul, Türkiye",
    addressComponents: [
      { longText: "74", shortText: "74", types: ["street_number"] },
      { longText: "Barbaros Bulvarı", shortText: "Barbaros Blv.", types: ["route"] },
      { longText: "Balmumcu", shortText: "Balmumcu", types: ["administrative_area_level_4", "political"] },
      { longText: "Beşiktaş", shortText: "Beşiktaş", types: ["administrative_area_level_2", "political"] },
      { longText: "İstanbul", shortText: "İstanbul", types: ["administrative_area_level_1", "political"] },
    ],
    location: { latitude: 41.0449616, longitude: 29.0076831 },
  },
  "emulator-fixture-incomplete": {
    id: "emulator-fixture-incomplete",
    formattedAddress: "Esentepe, Büyükdere Cd., İstanbul, Türkiye",
    addressComponents: [
      { longText: "Büyükdere Caddesi", shortText: "Büyükdere Cd.", types: ["route"] },
      { longText: "Esentepe", shortText: "Esentepe", types: ["administrative_area_level_4", "political"] },
      { longText: "İstanbul", shortText: "İstanbul", types: ["administrative_area_level_1", "political"] },
      // Deliberately no administrative_area_level_2 — mirrors the real
      // Maslak-query spike result where district came back missing.
    ],
    location: { latitude: 41.0777007, longitude: 29.0133881 },
  },
};

const emulatorSafeAutocomplete: AutocompleteFn = async (_apiKey, input) => {
  logger.info(`[googlePlacesClient] emulator/local context — not calling real Places API (input length ${input.length}).`);
  if (input.toLowerCase().includes("incomplete")) {
    return [{ placeId: "emulator-fixture-incomplete", text: "Esentepe, Büyükdere Cd., İstanbul, Türkiye" }];
  }
  if (input.trim().length === 0) return [];
  return [{ placeId: "emulator-fixture-besiktas", text: "Balmumcu, Barbaros Bulvarı No:74, Beşiktaş/İstanbul, Türkiye" }];
};

const emulatorSafePlaceDetails: PlaceDetailsFn = async (_apiKey, placeId, _sessionToken) => {
  logger.info(`[googlePlacesClient] emulator/local context — not calling real Places API (placeId ${placeId}).`);
  return EMULATOR_FIXTURE_PLACE_DETAILS[placeId] ?? null;
};

export function defaultAutocompleteFn(): AutocompleteFn {
  return isEmulatorContext() ? emulatorSafeAutocomplete : realAutocomplete;
}

export function defaultPlaceDetailsFn(): PlaceDetailsFn {
  return isEmulatorContext() ? emulatorSafePlaceDetails : realPlaceDetails;
}
