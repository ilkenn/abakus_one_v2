import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for Faz P.2.1's `reverseGeocodeAddressPoint`
 * callable — mirrors `deliveryPlaces.test.ts`'s exact pattern.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

async function signUpAnonymously(): Promise<{ idToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; localId: string };
  assert.strictEqual(response.status, 200, "Auth emulator sign-up must succeed");
  return { idToken: body.idToken, uid: body.localId };
}

test("reverseGeocodeAddressPoint: unauthenticated caller is rejected", async () => {
  const { body } = await callCallable(fn("reverseGeocodeAddressPoint"), {
    latitude: 41.05,
    longitude: 29.0,
  });
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("reverseGeocodeAddressPoint: missing coordinates are rejected", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(fn("reverseGeocodeAddressPoint"), {}, idToken);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("reverseGeocodeAddressPoint: a resolvable point returns a fully-resolved address (moved-pin re-verification)", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("reverseGeocodeAddressPoint"),
    { latitude: 41.05, longitude: 29.01 },
    idToken,
  );
  assert.strictEqual(body.result?.sufficientlyResolved, true);
  const resolved = body.result?.resolved as Record<string, unknown>;
  assert.strictEqual(resolved.districtName, "Beşiktaş");
  assert.ok((resolved.providerPlaceId as string).length > 0);
});

test("reverseGeocodeAddressPoint: an unresolvable point (sentinel 0,0) returns sufficientlyResolved=false, never throws", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("reverseGeocodeAddressPoint"),
    { latitude: 0, longitude: 0 },
    idToken,
  );
  assert.strictEqual(body.result?.sufficientlyResolved, false);
  const resolved = body.result?.resolved as Record<string, unknown>;
  assert.strictEqual(resolved.providerPlaceId, "");
});

// Paket Servis P.3 §D13 — the physical-device "address stuck on one
// location" root cause: the emulator-safe reverse-geocode fixture used to
// collapse every non-(0,0) coordinate onto the identical placeId. These
// tests prove two materially distant coordinates now produce genuinely
// independent results, and that repeated alternating calls never leak a
// stale/cached placeId across invocations.
test("reverseGeocodeAddressPoint: two materially distant coordinates resolve to two different, independent results", async () => {
  const { idToken } = await signUpAnonymously();

  const besiktasResponse = await callCallable(
    fn("reverseGeocodeAddressPoint"),
    { latitude: 41.05, longitude: 29.01 },
    idToken,
  );
  const kadikoyResponse = await callCallable(
    fn("reverseGeocodeAddressPoint"),
    { latitude: 40.99, longitude: 29.02 },
    idToken,
  );

  const besiktasResolved = besiktasResponse.body.result?.resolved as Record<string, unknown>;
  const kadikoyResolved = kadikoyResponse.body.result?.resolved as Record<string, unknown>;

  assert.strictEqual(besiktasResolved.districtName, "Beşiktaş");
  assert.strictEqual(kadikoyResolved.districtName, "Kadıköy");
  assert.notStrictEqual(besiktasResolved.providerPlaceId, kadikoyResolved.providerPlaceId);
  assert.notStrictEqual(besiktasResolved.formattedAddress, kadikoyResolved.formattedAddress);
});

test(
  "reverseGeocodeAddressPoint: alternating calls between two distant points never leak a stale/cached " +
    "placeId from the prior invocation — each call resolves independently",
  async () => {
    const { idToken } = await signUpAnonymously();
    const besiktas = { latitude: 41.05, longitude: 29.01 };
    const kadikoy = { latitude: 40.99, longitude: 29.02 };

    const sequence = [besiktas, kadikoy, besiktas, kadikoy, besiktas];
    const districts: unknown[] = [];
    for (const point of sequence) {
      const { body } = await callCallable(fn("reverseGeocodeAddressPoint"), point, idToken);
      const resolved = body.result?.resolved as Record<string, unknown>;
      districts.push(resolved.districtName);
    }

    assert.deepStrictEqual(districts, [
      "Beşiktaş",
      "Kadıköy",
      "Beşiktaş",
      "Kadıköy",
      "Beşiktaş",
    ]);
  },
);

test("reverseGeocodeAddressPoint: the same coordinate always resolves to the same result (deterministic, not merely non-crossing)", async () => {
  const { idToken } = await signUpAnonymously();
  const point = { latitude: 41.05, longitude: 29.01 };

  const first = await callCallable(fn("reverseGeocodeAddressPoint"), point, idToken);
  const second = await callCallable(fn("reverseGeocodeAddressPoint"), point, idToken);

  const firstResolved = first.body.result?.resolved as Record<string, unknown>;
  const secondResolved = second.body.result?.resolved as Record<string, unknown>;
  assert.strictEqual(firstResolved.providerPlaceId, secondResolved.providerPlaceId);
  assert.strictEqual(firstResolved.formattedAddress, secondResolved.formattedAddress);
});
