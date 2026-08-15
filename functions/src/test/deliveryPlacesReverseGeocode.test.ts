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
