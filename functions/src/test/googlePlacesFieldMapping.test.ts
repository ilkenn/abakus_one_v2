import { test } from "node:test";
import assert from "node:assert";
import {
  extractComponent,
  normalizePlaceDetails,
  isSufficientlyResolved,
  type RawPlaceDetails,
} from "../googlePlacesFieldMapping";

/**
 * Pure, no-emulator unit tests — Faz P.2. Fixtures are real captured
 * responses from the actual coverage spike against Google Places API
 * (New) for Beşiktaş/Kağıthane/Maslak (`docs/decisions.md` Faz P.2), not
 * invented shapes — proving the mapping logic against real evidence.
 */

const BESIKTAS_FIXTURE: RawPlaceDetails = {
  id: "ChIJ4ZezpaO3yhQRQP4fWxuhun4",
  formattedAddress: "Balmumcu, Barbaros Blv. No:74, 34349 Beşiktaş/İstanbul, Türkiye",
  addressComponents: [
    { longText: "74", shortText: "74", types: ["street_number"] },
    { longText: "Barbaros Bulvarı", shortText: "Barbaros Blv.", types: ["route"] },
    { longText: "Balmumcu", shortText: "Balmumcu", types: ["administrative_area_level_4", "political"] },
    { longText: "Beşiktaş", shortText: "Beşiktaş", types: ["administrative_area_level_2", "political"] },
    { longText: "İstanbul", shortText: "İstanbul", types: ["administrative_area_level_1", "political"] },
    { longText: "Türkiye", shortText: "TR", types: ["country", "political"] },
    { longText: "34349", shortText: "34349", types: ["postal_code"] },
  ],
  location: { latitude: 41.0449616, longitude: 29.0076831 },
};

// Real spike result — a mahalle-level query with no street in it, so no
// route/street_number by construction (not a provider failure).
const KAGITHANE_FIXTURE: RawPlaceDetails = {
  id: "ChIJfRI7XV62yhQRYn7zSycgmv8",
  formattedAddress: "Ortabayır, 34413 Kağıthane/İstanbul, Türkiye",
  addressComponents: [
    { longText: "Ortabayır", shortText: "Ortabayır", types: ["administrative_area_level_4", "political"] },
    { longText: "Kağıthane", shortText: "Kağıthane", types: ["administrative_area_level_2", "political"] },
    { longText: "İstanbul", shortText: "İstanbul", types: ["administrative_area_level_1", "political"] },
  ],
  location: { latitude: 41.078883, longitude: 29.003801 },
};

// Real spike result — the Maslak query's top autocomplete suggestion
// resolved to a real place with NO administrative_area_level_2 at all.
const MASLAK_MISSING_DISTRICT_FIXTURE: RawPlaceDetails = {
  id: "EjpFc2VudGVwZSwgQsO8ecO8a2RlcmUgQ2FkZGVzaSwgxZ5pxZ9saS_EsHN0YW5idWwsIFTDvHJraXllIi4qLAoUChIJo45o49a1yhQRrI6gRiN5ZZ8SFAoSCXUlpH5btsoUEQcOJ9gql8H4",
  formattedAddress: "Esentepe, Büyükdere Cd., İstanbul, Türkiye",
  addressComponents: [
    { longText: "Büyükdere Caddesi", shortText: "Büyükdere Cd.", types: ["route"] },
    { longText: "Esentepe", shortText: "Esentepe", types: ["administrative_area_level_4", "political"] },
    { longText: "İstanbul", shortText: "İstanbul", types: ["administrative_area_level_1", "political"] },
  ],
  location: { latitude: 41.0777007, longitude: 29.0133881 },
};

test("extractComponent finds a component by type", () => {
  const result = extractComponent(BESIKTAS_FIXTURE.addressComponents, ["administrative_area_level_2"]);
  assert.strictEqual(result?.longText, "Beşiktaş");
});

test("extractComponent returns null when no component matches", () => {
  const result = extractComponent(KAGITHANE_FIXTURE.addressComponents, ["street_number"]);
  assert.strictEqual(result, null);
});

test("extractComponent returns null for undefined/malformed components (fails closed)", () => {
  assert.strictEqual(extractComponent(undefined, ["route"]), null);
  assert.strictEqual(extractComponent([], ["route"]), null);
});

test("normalizePlaceDetails: full resolution — province/district/neighborhood/street/building all map correctly (req 5-8)", () => {
  const result = normalizePlaceDetails(BESIKTAS_FIXTURE.id!, BESIKTAS_FIXTURE);
  assert.strictEqual(result.provinceName, "İstanbul");
  assert.strictEqual(result.districtName, "Beşiktaş");
  assert.strictEqual(result.neighborhoodName, "Balmumcu");
  assert.strictEqual(result.routeName, "Barbaros Bulvarı");
  assert.strictEqual(result.streetNumber, "74");
  assert.strictEqual(result.latitude, 41.0449616);
  assert.strictEqual(result.longitude, 29.0076831);
  assert.strictEqual(result.providerPlaceId, BESIKTAS_FIXTURE.id);
});

test("normalizePlaceDetails: neighborhood maps when the provider supplies it (req 6)", () => {
  const result = normalizePlaceDetails(KAGITHANE_FIXTURE.id!, KAGITHANE_FIXTURE);
  assert.strictEqual(result.neighborhoodName, "Ortabayır");
});

test("normalizePlaceDetails: route/streetNumber are null, not fabricated, when the provider genuinely has none (req 7, 8)", () => {
  const result = normalizePlaceDetails(KAGITHANE_FIXTURE.id!, KAGITHANE_FIXTURE);
  assert.strictEqual(result.routeName, null);
  assert.strictEqual(result.streetNumber, null);
});

test("normalizePlaceDetails: a place with no administrative_area_level_2 maps district as null, never fabricated", () => {
  const result = normalizePlaceDetails(
    MASLAK_MISSING_DISTRICT_FIXTURE.id!,
    MASLAK_MISSING_DISTRICT_FIXTURE,
  );
  assert.strictEqual(result.districtName, null);
  assert.strictEqual(result.provinceName, "İstanbul");
});

test("normalizePlaceDetails: a malformed/empty raw response fails closed to all-null fields, never throws (req 10)", () => {
  const result = normalizePlaceDetails("some-place-id", {});
  assert.strictEqual(result.provinceName, null);
  assert.strictEqual(result.districtName, null);
  assert.strictEqual(result.neighborhoodName, null);
  assert.strictEqual(result.latitude, null);
  assert.strictEqual(result.longitude, null);
  assert.strictEqual(result.formattedAddress, null);
});

test("isSufficientlyResolved: true when province+district+coordinates are all present", () => {
  const result = normalizePlaceDetails(BESIKTAS_FIXTURE.id!, BESIKTAS_FIXTURE);
  assert.strictEqual(isSufficientlyResolved(result), true);
});

test("isSufficientlyResolved: false when district is missing, even with province+coordinates present", () => {
  const result = normalizePlaceDetails(
    MASLAK_MISSING_DISTRICT_FIXTURE.id!,
    MASLAK_MISSING_DISTRICT_FIXTURE,
  );
  assert.strictEqual(isSufficientlyResolved(result), false);
});

test("isSufficientlyResolved: false for a fully malformed response", () => {
  const result = normalizePlaceDetails("some-place-id", {});
  assert.strictEqual(isSufficientlyResolved(result), false);
});
