#!/usr/bin/env node
// Faz P.2 §1 follow-up — checks whether Maslak/Okmeydanı resolve cleanly
// when a more specific autocomplete suggestion (not necessarily rank #1)
// is selected, since the initial spike's blind "always take suggestion 0"
// simplification is not representative of the real UX (user picks from a
// list). Same key-handling discipline as coverage_spike_places.mjs.

import { execSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const PROJECT_ID = "abakus-one-dev";
const SECRET_NAME = "GOOGLE_PLACES_SERVER_KEY";

function fetchSecret() {
  // SECURITY: see coverage_spike_places.mjs's fetchSecret for the full
  // reasoning — never let a raw secret value escape via a thrown/logged
  // error object.
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
  raw = null;
  if (!value || value.length < 10) {
    throw new Error("Could not read a plausible secret value from the CLI output.");
  }
  return value;
}

const ISTANBUL_BIAS = {
  circle: { center: { latitude: 41.0082, longitude: 28.9784 }, radius: 50000.0 },
};

async function autocomplete(apiKey, input) {
  const res = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Goog-Api-Key": apiKey },
    body: JSON.stringify({ input, includedRegionCodes: ["tr"], languageCode: "tr", locationBias: ISTANBUL_BIAS }),
  });
  return res.json();
}

async function placeDetails(apiKey, placeId) {
  const fieldMask = ["id", "formattedAddress", "addressComponents", "location"].join(",");
  const res = await fetch(`https://places.googleapis.com/v1/places/${placeId}`, {
    method: "GET",
    headers: { "X-Goog-Api-Key": apiKey, "X-Goog-FieldMask": fieldMask },
  });
  return res.json();
}

function extractComponent(addressComponents, types) {
  if (!Array.isArray(addressComponents)) return null;
  const match = addressComponents.find((c) => Array.isArray(c.types) && c.types.some((t) => types.includes(t)));
  return match ? { longText: match.longText, types: match.types } : null;
}

const QUERIES = [
  "Okmeydanı, Şişli, İstanbul",
  "Halil Rıfat Paşa Mahallesi, Şişli, İstanbul",
  "Maslak Mahallesi, Sarıyer, İstanbul",
  "Maslak Büyükdere Caddesi 255, Sarıyer, İstanbul",
];

async function main() {
  const apiKey = fetchSecret();
  console.log(`[followup] secret retrieved (length ${apiKey.length}, value not logged).`);
  const results = [];

  for (const query of QUERIES) {
    console.log(`\n[followup] === query: "${query}" ===`);
    const ac = await autocomplete(apiKey, query);
    const suggestions = (ac.suggestions ?? []).slice(0, 5);
    console.log(`[followup] ${suggestions.length} suggestion(s):`);
    for (const s of suggestions) {
      console.log(`  - ${s.placePrediction?.text?.text}`);
    }

    const entry = { query, suggestions: suggestions.map((s) => s.placePrediction?.text?.text) };
    entry.resolvedPerSuggestion = [];

    for (const s of suggestions.slice(0, 3)) {
      const placeId = s.placePrediction?.placeId;
      if (!placeId) continue;
      const details = await placeDetails(apiKey, placeId);
      const components = details.addressComponents;
      const resolved = {
        text: s.placePrediction?.text?.text,
        formattedAddress: details.formattedAddress ?? null,
        district: extractComponent(components, ["administrative_area_level_2"]),
        neighborhood: extractComponent(components, ["administrative_area_level_4"]),
      };
      entry.resolvedPerSuggestion.push(resolved);
      console.log(`    -> district=${resolved.district?.longText ?? "null"}, neighborhood=${resolved.neighborhood?.longText ?? "null"}`);
    }
    results.push(entry);
  }

  writeFileSync(new URL("./coverage_spike_followup_results.json", import.meta.url), JSON.stringify(results, null, 2), "utf8");
  console.log("\n[followup] wrote results.");
}

main().catch((err) => {
  // SECURITY: log only `err.message`, never the error object itself.
  console.error("[followup] FATAL:", err instanceof Error ? err.message : "unknown error");
  process.exitCode = 1;
});
