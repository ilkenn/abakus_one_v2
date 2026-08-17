import * as logger from "firebase-functions/logger";
import { resolveGoogleMapsProviderMode } from "./googleMapsProviderMode";
import type { RawPlaceDetails } from "./googlePlacesFieldMapping";

/**
 * The one seam that makes the delivery-address callables testable without
 * real network access or a real Google API key — mirrors
 * `reservationNotificationDelivery.ts`'s `PushSender`/`defaultSender()`
 * pattern exactly (§18 of that file's own doc comment): [defaultAutocompleteFn]/
 * [defaultPlaceDetailsFn] consult [resolveGoogleMapsProviderMode] — never
 * emulator presence (Paket Servis P.3 §D17) — to decide whether to
 * substitute a safe, deterministic fixture (fixture mode: automated tests
 * only) or call the real API (live mode: physical development, staging,
 * production). No caching of Google data is implemented (Faz P.2 §12 —
 * "do not invent unsupported caching of Google data"); every live-mode
 * call is a real request against the live API.
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

/**
 * Deterministic, offline fixture catalog — never a real network call,
 * never reads a real API key. One entry drives BOTH `emulatorSafe
 * Autocomplete` (matched by [keywords] against the query) and
 * `emulatorSafePlaceDetails` (looked up by [placeId]) — a single source of
 * truth, so the two can never drift apart the way the old, separate
 * hand-written switch statements did.
 *
 * **Paket Servis P.3 §D15 — the "Adres Ara only ever shows Balmumcu" root
 * cause, properly fixed** (`docs/decisions.md`): the previous fixture
 * table covered only 2–3 named places and silently defaulted *every other*
 * query to the Beşiktaş/Balmumcu fixture — so a real developer typing a
 * real neighborhood name during physical testing always got the same
 * result back, indistinguishable from "search does nothing." This table
 * covers every neighborhood named in the P.3 device-UX correction,
 * spanning all 5 real delivery districts (Beşiktaş, Şişli, Beyoğlu,
 * Kağıthane, Sarıyer) **plus** Kadıköy, deliberately kept as the one
 * out-of-service fixture (delivery eligibility is a separate,
 * server-authoritative concern from address *search* — search must never
 * artificially hide or misrepresent an out-of-area place). A query that
 * matches none of these keywords now returns **no suggestions** rather
 * than silently falling back to Balmumcu — matching what a real "no
 * results for this query" search actually looks like, never masquerading
 * an unrelated query as a Balmumcu match.
 *
 * Coordinates are approximate, real-world-plausible Istanbul locations —
 * good enough as map-search test fixtures, not an authoritative geocoding
 * claim (the same "not a delivery-zone claim" caveat `MapFirstAddress
 * Screen.istanbulDefault` already documents). Maslak in particular is
 * simplified to one point for fixture purposes only — `docs/decisions.md`
 * Faz P.2 already established that "Maslak" is a colloquial operational
 * label spanning several real mahalles, never one Google-resolvable value;
 * this fixture does not contradict that, it only needs *a* plausible point
 * to search-test with.
 */
interface EmulatorPlaceFixture {
  placeId: string;
  /** Lowercase substrings matched against the (lowercased) query. */
  keywords: string[];
  text: string;
  details: RawPlaceDetails;
}

function fixture(
  id: string,
  keywords: string[],
  formattedAddress: string,
  route: string | null,
  streetNumber: string | null,
  neighborhood: string,
  district: string | null,
  location: { latitude: number; longitude: number },
): EmulatorPlaceFixture {
  const addressComponents: RawPlaceDetails["addressComponents"] = [];
  if (streetNumber) addressComponents.push({ longText: streetNumber, shortText: streetNumber, types: ["street_number"] });
  if (route) addressComponents.push({ longText: route, shortText: route, types: ["route"] });
  addressComponents.push({ longText: neighborhood, shortText: neighborhood, types: ["administrative_area_level_4", "political"] });
  if (district) addressComponents.push({ longText: district, shortText: district, types: ["administrative_area_level_2", "political"] });
  addressComponents.push({ longText: "İstanbul", shortText: "İstanbul", types: ["administrative_area_level_1", "political"] });
  return {
    placeId: id,
    keywords,
    text: formattedAddress,
    details: { id, formattedAddress, addressComponents, location },
  };
}

const EMULATOR_PLACE_FIXTURES: readonly EmulatorPlaceFixture[] = [
  fixture(
    "emulator-fixture-incomplete",
    ["incomplete"],
    "Esentepe, Büyükdere Cd., İstanbul, Türkiye",
    "Büyükdere Caddesi",
    null,
    "Esentepe",
    null, // Deliberately no district — mirrors the real Maslak-query spike result where district came back missing.
    { latitude: 41.0777007, longitude: 29.0133881 },
  ),
  fixture(
    "emulator-fixture-besiktas", // Balmumcu — the original, unchanged fixture (existing tests/docs reference this placeId directly).
    ["balmumcu", "barbaros"],
    "Balmumcu, Barbaros Blv. No:74, 34349 Beşiktaş/İstanbul, Türkiye",
    "Barbaros Bulvarı",
    "74",
    "Balmumcu",
    "Beşiktaş",
    { latitude: 41.0449616, longitude: 29.0076831 },
  ),
  fixture(
    "emulator-fixture-ortakoy",
    ["ortaköy", "ortakoy"],
    "Ortaköy, Muallim Naci Cd., 34347 Beşiktaş/İstanbul, Türkiye",
    "Muallim Naci Caddesi",
    null,
    "Ortaköy",
    "Beşiktaş",
    { latitude: 41.0553, longitude: 29.027 },
  ),
  fixture(
    "emulator-fixture-besiktas-merkez",
    ["beşiktaş", "besiktas"],
    "Beşiktaş, Çırağan Cd., 34353 Beşiktaş/İstanbul, Türkiye",
    "Çırağan Caddesi",
    null,
    "Beşiktaş",
    "Beşiktaş",
    { latitude: 41.0422, longitude: 29.0093 },
  ),
  fixture(
    "emulator-fixture-levent",
    ["levent"],
    "Levent, Büyükdere Cd., 34330 Beşiktaş/İstanbul, Türkiye",
    "Büyükdere Caddesi",
    null,
    "Levent",
    "Beşiktaş",
    { latitude: 41.0814, longitude: 29.0094 },
  ),
  fixture(
    "emulator-fixture-etiler",
    ["etiler"],
    "Etiler, Nispetiye Cd., 34337 Beşiktaş/İstanbul, Türkiye",
    "Nispetiye Caddesi",
    null,
    "Etiler",
    "Beşiktaş",
    { latitude: 41.0781, longitude: 29.0339 },
  ),
  fixture(
    "emulator-fixture-nisantasi",
    ["nişantaşı", "nisantasi"],
    "Nişantaşı, Teşvikiye Cd., 34365 Şişli/İstanbul, Türkiye",
    "Teşvikiye Caddesi",
    null,
    "Nişantaşı",
    "Şişli",
    { latitude: 41.0476, longitude: 28.9938 },
  ),
  fixture(
    "emulator-fixture-sisli",
    ["şişli", "sisli"],
    "Şişli, Halaskargazi Cd., 34360 Şişli/İstanbul, Türkiye",
    "Halaskargazi Caddesi",
    null,
    "Şişli",
    "Şişli",
    { latitude: 41.0602, longitude: 28.9877 },
  ),
  fixture(
    "emulator-fixture-taksim",
    ["taksim"],
    "Taksim, İstiklal Cd., 34435 Beyoğlu/İstanbul, Türkiye",
    "İstiklal Caddesi",
    null,
    "Taksim",
    "Beyoğlu",
    { latitude: 41.037, longitude: 28.9857 },
  ),
  fixture(
    "emulator-fixture-beyoglu",
    ["beyoğlu", "beyoglu"],
    "Beyoğlu, Meşrutiyet Cd., 34430 Beyoğlu/İstanbul, Türkiye",
    "Meşrutiyet Caddesi",
    null,
    "Beyoğlu",
    "Beyoğlu",
    { latitude: 41.0328, longitude: 28.976 },
  ),
  fixture(
    "emulator-fixture-kagithane",
    ["kağıthane", "kagithane"],
    "Kağıthane, Merkez Mah., 34406 Kağıthane/İstanbul, Türkiye",
    null,
    null,
    "Merkez",
    "Kağıthane",
    { latitude: 41.0808, longitude: 28.9647 },
  ),
  fixture(
    "emulator-fixture-maslak",
    ["maslak"],
    "Maslak, Büyükdere Cd., 34485 Sarıyer/İstanbul, Türkiye",
    "Büyükdere Caddesi",
    null,
    "Maslak",
    "Sarıyer",
    { latitude: 41.1105, longitude: 29.0219 },
  ),
  fixture(
    "emulator-fixture-sariyer",
    ["sarıyer", "sariyer"],
    "Sarıyer, Merkez Mah., 34450 Sarıyer/İstanbul, Türkiye",
    null,
    null,
    "Merkez",
    "Sarıyer",
    { latitude: 41.1673, longitude: 29.0568 },
  ),
  // Deliberately the one OUT-OF-SERVICE fixture — Kadıköy is not one of
  // the 5 real delivery districts. Address *search* must never hide or
  // special-case it; delivery eligibility is checked separately, after
  // selection (see this callable's own doc comment and `docs/business_
  // rules.md` BR-DELIVERY-008).
  fixture(
    "emulator-fixture-kadikoy",
    ["kadıköy", "kadikoy"],
    "Caferağa, Moda Cd. No:12, 34710 Kadıköy/İstanbul, Türkiye",
    "Moda Caddesi",
    "12",
    "Caferağa",
    "Kadıköy",
    { latitude: 40.9922, longitude: 29.0244 },
  ),
];

const EMULATOR_FIXTURE_PLACE_DETAILS: Record<string, RawPlaceDetails> = Object.fromEntries(
  EMULATOR_PLACE_FIXTURES.map((f) => [f.placeId, f.details]),
);

const emulatorSafeAutocomplete: AutocompleteFn = async (_apiKey, input) => {
  logger.info(`[googlePlacesClient] emulator/local context — not calling real Places API (input length ${input.length}).`);
  if (input.trim().length === 0) return [];
  const normalized = input.toLowerCase();
  const match = EMULATOR_PLACE_FIXTURES.find((f) => f.keywords.some((keyword) => normalized.includes(keyword)));
  // No keyword match — a genuinely unknown query returns no suggestions,
  // exactly like a real "no results" search, never a silent Balmumcu
  // fallback (Paket Servis P.3 §D15).
  if (!match) return [];
  return [{ placeId: match.placeId, text: match.text }];
};

const emulatorSafePlaceDetails: PlaceDetailsFn = async (_apiKey, placeId, _sessionToken) => {
  logger.info(`[googlePlacesClient] emulator/local context — not calling real Places API (placeId ${placeId}).`);
  return EMULATOR_FIXTURE_PLACE_DETAILS[placeId] ?? null;
};

export function defaultAutocompleteFn(): AutocompleteFn {
  return resolveGoogleMapsProviderMode() === "fixture" ? emulatorSafeAutocomplete : realAutocomplete;
}

export function defaultPlaceDetailsFn(): PlaceDetailsFn {
  return resolveGoogleMapsProviderMode() === "fixture" ? emulatorSafePlaceDetails : realPlaceDetails;
}
