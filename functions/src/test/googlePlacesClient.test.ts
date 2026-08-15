import { test } from "node:test";
import assert from "node:assert";
import { buildAutocompleteRequestBody } from "../googlePlacesClient";

/** Pure, no-emulator/no-network unit tests — Faz P.2 §13 req 2, 3. */

test("buildAutocompleteRequestBody restricts to Turkey (req 2)", () => {
  const body = buildAutocompleteRequestBody("Barbaros Bulvarı", "session-1");
  assert.deepStrictEqual(body.includedRegionCodes, ["tr"]);
});

test("buildAutocompleteRequestBody applies an Istanbul location bias (req 3)", () => {
  const body = buildAutocompleteRequestBody("Barbaros Bulvarı", "session-1") as {
    locationBias: { circle: { center: { latitude: number; longitude: number }; radius: number } };
  };
  // Istanbul's real coordinates, not e.g. (0,0) or omitted entirely.
  assert.ok(Math.abs(body.locationBias.circle.center.latitude - 41.0082) < 0.5);
  assert.ok(Math.abs(body.locationBias.circle.center.longitude - 28.9784) < 0.5);
  assert.ok(body.locationBias.circle.radius > 0);
});

test("buildAutocompleteRequestBody forwards the caller's input and sessionToken unchanged", () => {
  const body = buildAutocompleteRequestBody("İstiklal Caddesi", "session-abc");
  assert.strictEqual(body.input, "İstiklal Caddesi");
  assert.strictEqual(body.sessionToken, "session-abc");
});
