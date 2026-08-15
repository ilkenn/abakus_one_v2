#!/usr/bin/env node
// Faz P.2 §1 — Google Places API (New) coverage spike. One-off,
// developer-run diagnostic script — NOT part of the deployed Functions
// bundle, NOT imported by any production module. Mirrors this directory's
// existing `seed_dev_*.mjs` "admin script, not production code" pattern.
//
// Security: the raw API key is fetched into this process's own memory via
// `firebase functions:secrets:access` and used ONLY as an outgoing HTTP
// header value. It is never printed, logged, written to a file, or
// returned in this script's own output — only the parsed, structured
// Places API responses are.
//
// Usage: node scripts/coverage_spike_places.mjs

import { execSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const PROJECT_ID = "abakus-one-dev";
const SECRET_NAME = "GOOGLE_PLACES_SERVER_KEY";

function fetchSecret() {
  // SECURITY: never let a raw secret value escape this function — not via
  // a thrown error, not via a caught-and-logged exception. `execSync`
  // attaches captured stdout to its thrown Error's own `.stdout`/`.output`
  // properties on a non-zero exit; a naive `catch (err) { console.log(err) }`
  // upstream would print the secret even though *this* function's own
  // happy path never does. So: catch here, discard the error object
  // entirely (never re-throw it, never log any of its properties), and
  // throw a new, description-only Error instead.
  let raw;
  try {
    raw = execSync(
      `firebase functions:secrets:access ${SECRET_NAME} --project ${PROJECT_ID}`,
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
    );
  } catch {
    throw new Error(
      `Failed to access secret "${SECRET_NAME}" via the Firebase CLI (command exited non-zero). ` +
        "Not logging the underlying error — it may carry captured stdout.",
    );
  }
  const lines = raw.split("\n").map((l) => l.trim()).filter(Boolean);
  const value = lines[lines.length - 1];
  raw = null; // drop the only other reference to the full raw output promptly
  if (!value || value.length < 10) {
    throw new Error("Could not read a plausible secret value from the CLI output.");
  }
  return value;
}

// Representative samples — Faz P.2 §1's named districts plus the two named
// operational areas (Maslak, Okmeydanı, both intersections/sub-areas of
// formal ilçe boundaries, not ilçe themselves).
const SAMPLES = [
  { area: "Beşiktaş", query: "Barbaros Bulvarı No:74, Beşiktaş, İstanbul" },
  { area: "Şişli", query: "Halaskargazi Caddesi No:150, Şişli, İstanbul" },
  { area: "Beyoğlu", query: "İstiklal Caddesi No:80, Beyoğlu, İstanbul" },
  { area: "Kağıthane", query: "Ortabayır Mahallesi, Kağıthane, İstanbul" },
  { area: "Sarıyer", query: "Büyükdere Caddesi No:120, Sarıyer, İstanbul" },
  { area: "Maslak (operational area)", query: "Maslak Mahallesi, Büyükdere Caddesi, Sarıyer, İstanbul" },
  { area: "Okmeydanı (operational area)", query: "Okmeydanı Mahallesi, Şişli, İstanbul" },
];

// Istanbul-wide location bias circle (Faz P.2 §3 — geographic bias toward
// Istanbul/our operating area).
const ISTANBUL_BIAS = {
  circle: {
    center: { latitude: 41.0082, longitude: 28.9784 },
    radius: 50000.0,
  },
};

async function autocomplete(apiKey, input) {
  const res = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
    },
    body: JSON.stringify({
      input,
      includedRegionCodes: ["tr"],
      languageCode: "tr",
      locationBias: ISTANBUL_BIAS,
    }),
  });
  const status = res.status;
  const json = await res.json().catch(() => null);
  return { status, json };
}

async function placeDetails(apiKey, placeId) {
  const fieldMask = [
    "id",
    "formattedAddress",
    "shortFormattedAddress",
    "addressComponents",
    "location",
  ].join(",");
  const res = await fetch(`https://places.googleapis.com/v1/places/${placeId}`, {
    method: "GET",
    headers: {
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": fieldMask,
    },
  });
  const status = res.status;
  const json = await res.json().catch(() => null);
  return { status, json };
}

function extractComponent(addressComponents, types) {
  if (!Array.isArray(addressComponents)) return null;
  const match = addressComponents.find((c) =>
    Array.isArray(c.types) && c.types.some((t) => types.includes(t)),
  );
  return match ? { longText: match.longText, shortText: match.shortText, types: match.types } : null;
}

async function main() {
  console.log(`[coverage-spike] fetching secret "${SECRET_NAME}" from project "${PROJECT_ID}"...`);
  const apiKey = fetchSecret();
  console.log(`[coverage-spike] secret retrieved (length ${apiKey.length}, value not logged).`);

  const results = [];

  for (const sample of SAMPLES) {
    console.log(`\n[coverage-spike] === ${sample.area} — query: "${sample.query}" ===`);
    const entry = { area: sample.area, query: sample.query };

    let autocompleteResult;
    try {
      autocompleteResult = await autocomplete(apiKey, sample.query);
    } catch (err) {
      entry.autocompleteError = String(err);
      results.push(entry);
      console.log(`[coverage-spike] autocomplete FAILED: ${err}`);
      continue;
    }

    entry.autocompleteStatus = autocompleteResult.status;
    if (autocompleteResult.status !== 200) {
      entry.autocompleteError = autocompleteResult.json;
      results.push(entry);
      console.log(`[coverage-spike] autocomplete HTTP ${autocompleteResult.status}:`, JSON.stringify(autocompleteResult.json));
      continue;
    }

    const suggestions = autocompleteResult.json?.suggestions ?? [];
    entry.suggestionCount = suggestions.length;
    entry.topSuggestions = suggestions.slice(0, 3).map((s) => ({
      placeId: s.placePrediction?.placeId,
      text: s.placePrediction?.text?.text,
    }));

    if (suggestions.length === 0) {
      results.push(entry);
      console.log(`[coverage-spike] NO SUGGESTIONS returned.`);
      continue;
    }

    const topPlaceId = suggestions[0].placePrediction?.placeId;
    entry.resolvedPlaceId = topPlaceId;

    let detailsResult;
    try {
      detailsResult = await placeDetails(apiKey, topPlaceId);
    } catch (err) {
      entry.detailsError = String(err);
      results.push(entry);
      console.log(`[coverage-spike] place details FAILED: ${err}`);
      continue;
    }

    entry.detailsStatus = detailsResult.status;
    if (detailsResult.status !== 200) {
      entry.detailsError = detailsResult.json;
      results.push(entry);
      console.log(`[coverage-spike] place details HTTP ${detailsResult.status}:`, JSON.stringify(detailsResult.json));
      continue;
    }

    const place = detailsResult.json;
    const components = place.addressComponents;

    entry.formattedAddress = place.formattedAddress ?? null;
    entry.shortFormattedAddress = place.shortFormattedAddress ?? null;
    entry.latitude = place.location?.latitude ?? null;
    entry.longitude = place.location?.longitude ?? null;
    entry.province = extractComponent(components, ["administrative_area_level_1"]);
    entry.district = extractComponent(components, ["administrative_area_level_2"]);
    entry.adminArea3 = extractComponent(components, ["administrative_area_level_3"]);
    entry.adminArea4 = extractComponent(components, ["administrative_area_level_4"]);
    entry.neighborhoodSublocality1 = extractComponent(components, ["sublocality_level_1", "sublocality"]);
    entry.neighborhoodSublocality2 = extractComponent(components, ["sublocality_level_2"]);
    entry.locality = extractComponent(components, ["locality"]);
    entry.route = extractComponent(components, ["route"]);
    entry.streetNumber = extractComponent(components, ["street_number"]);
    entry.postalCode = extractComponent(components, ["postal_code"]);
    entry.allComponentTypes = Array.isArray(components)
      ? components.map((c) => c.types).flat()
      : [];

    results.push(entry);
    console.log(`[coverage-spike] formattedAddress: ${entry.formattedAddress}`);
    console.log(`[coverage-spike] province: ${JSON.stringify(entry.province)}`);
    console.log(`[coverage-spike] district (admin_area_2): ${JSON.stringify(entry.district)}`);
    console.log(`[coverage-spike] admin_area_4 (neighborhood candidate?): ${JSON.stringify(entry.adminArea4)}`);
    console.log(`[coverage-spike] locality: ${JSON.stringify(entry.locality)}`);
    console.log(`[coverage-spike] sublocality_1 (neighborhood?): ${JSON.stringify(entry.neighborhoodSublocality1)}`);
    console.log(`[coverage-spike] sublocality_2: ${JSON.stringify(entry.neighborhoodSublocality2)}`);
    console.log(`[coverage-spike] route: ${JSON.stringify(entry.route)}`);
    console.log(`[coverage-spike] street_number: ${JSON.stringify(entry.streetNumber)}`);
    console.log(`[coverage-spike] lat/lng: ${entry.latitude}, ${entry.longitude}`);
  }

  const outPath = new URL("./coverage_spike_results.json", import.meta.url);
  writeFileSync(outPath, JSON.stringify(results, null, 2), "utf8");
  console.log(`\n[coverage-spike] wrote structured results (no key) to ${outPath.pathname}`);
}

main().catch((err) => {
  // SECURITY: log only `err.message` (a plain string we control the
  // content of throughout this file), never the error object itself —
  // never `err`, never `err.stdout`/`err.output`, which for a failed
  // `execSync` call can carry captured process output.
  console.error("[coverage-spike] FATAL:", err instanceof Error ? err.message : "unknown error");
  process.exitCode = 1;
});
