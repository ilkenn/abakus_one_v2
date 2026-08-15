import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { getFirestore } from "firebase-admin/firestore";

/**
 * Emulator-backed tests for Faz P.2's three delivery-address callables —
 * mirrors `registerDeviceToken.test.ts`'s exact pattern (raw HTTP against
 * the callable-functions wire protocol, anonymous-sign-up-minted
 * identities). Exercises the emulator-safe fake Places client
 * (`googlePlacesClient.ts`'s `defaultAutocompleteFn`/`defaultPlaceDetailsFn`
 * short-circuit under `FIRESTORE_EMULATOR_HOST`) — never the real Google
 * API, never the real secret.
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

// ---------------------------------------------------------------------
// searchAddressAutocomplete
// ---------------------------------------------------------------------

test("searchAddressAutocomplete: unauthenticated caller is rejected", async () => {
  const { body } = await callCallable(fn("searchAddressAutocomplete"), {
    input: "Beşiktaş",
    sessionToken: "session-1",
  });
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("searchAddressAutocomplete: empty input returns an empty list, no error", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("searchAddressAutocomplete"),
    { input: "", sessionToken: "session-1" },
    idToken,
  );
  assert.deepStrictEqual(body.result?.suggestions, []);
});

test("searchAddressAutocomplete: missing sessionToken is rejected", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("searchAddressAutocomplete"),
    { input: "Beşiktaş" },
    idToken,
  );
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("searchAddressAutocomplete: a real input returns the emulator-safe fixture suggestion", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("searchAddressAutocomplete"),
    { input: "Barbaros Bulvarı", sessionToken: "session-1" },
    idToken,
  );
  const suggestions = body.result?.suggestions as { placeId: string; text: string }[];
  assert.ok(suggestions.length > 0);
  assert.strictEqual(suggestions[0].placeId, "emulator-fixture-besiktas");
});

// ---------------------------------------------------------------------
// resolveAddressPlace
// ---------------------------------------------------------------------

test("resolveAddressPlace: unauthenticated caller is rejected", async () => {
  const { body } = await callCallable(fn("resolveAddressPlace"), {
    placeId: "emulator-fixture-besiktas",
    sessionToken: "session-1",
  });
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("resolveAddressPlace: an unknown place id is rejected (req 11)", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("resolveAddressPlace"),
    { placeId: "totally-unknown-place-id", sessionToken: "session-1" },
    idToken,
  );
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("resolveAddressPlace: a fully resolved fixture returns sufficientlyResolved=true", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("resolveAddressPlace"),
    { placeId: "emulator-fixture-besiktas", sessionToken: "session-1" },
    idToken,
  );
  assert.strictEqual(body.result?.sufficientlyResolved, true);
  const resolved = body.result?.resolved as Record<string, unknown>;
  assert.strictEqual(resolved.districtName, "Beşiktaş");
  assert.strictEqual(resolved.streetNumber, "74");
});

test("resolveAddressPlace: an incomplete fixture (missing district) returns sufficientlyResolved=false", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("resolveAddressPlace"),
    { placeId: "emulator-fixture-incomplete", sessionToken: "session-1" },
    idToken,
  );
  assert.strictEqual(body.result?.sufficientlyResolved, false);
});

// ---------------------------------------------------------------------
// saveDeliveryAddress
// ---------------------------------------------------------------------

test("saveDeliveryAddress: unauthenticated caller is rejected", async () => {
  const { body } = await callCallable(fn("saveDeliveryAddress"), {
    placeId: "emulator-fixture-besiktas",
    label: "Ev",
    apartmentNo: "4",
  });
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("saveDeliveryAddress: apartmentNo is required (Faz P.2 §6, req always customer input)", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    { placeId: "emulator-fixture-besiktas", label: "Ev" },
    idToken,
  );
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("saveDeliveryAddress: a fully resolvable place is saved as verified, "
  + "with server-derived fields — client-supplied bogus location data is "
  + "ignored (req 12, 13)", async () => {
  const { idToken, uid } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-besiktas",
      label: "Ev",
      apartmentNo: "4",
      // Deliberately bogus/malicious values a client might send — must be
      // completely ignored; the callable never even reads these keys.
      verificationStatus: "verified",
      verifiedAt: "2020-01-01T00:00:00.000Z",
      provinceName: "FAKE",
      districtName: "FAKE",
      latitude: 0,
      longitude: 0,
    },
    idToken,
  );
  assert.strictEqual(body.result?.verificationStatus, "verified");
  const addressId = body.result?.addressId as string;

  const doc = await getFirestore().collection("customerAddresses").doc(addressId).get();
  const data = doc.data()!;
  assert.strictEqual(data.uid, uid);
  assert.strictEqual(data.verificationStatus, "verified");
  assert.strictEqual(data.provinceName, "İstanbul");
  assert.strictEqual(data.districtName, "Beşiktaş");
  assert.strictEqual(data.latitude, 41.0449616);
  assert.strictEqual(data.buildingNo, "74");
  assert.strictEqual(data.buildingNoSource, "provider");
  assert.notStrictEqual(data.verifiedAt, "2020-01-01T00:00:00.000Z");
});

test("saveDeliveryAddress: an incompletely resolved place is saved as "
  + "unverified, not rejected (§5 'keep it unverified')", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    { placeId: "emulator-fixture-incomplete", label: "İş", apartmentNo: "2" },
    idToken,
  );
  assert.strictEqual(body.result?.verificationStatus, "unverified");
  const addressId = body.result?.addressId as string;
  const doc = await getFirestore().collection("customerAddresses").doc(addressId).get();
  const data = doc.data()!;
  assert.strictEqual(data.verificationStatus, "unverified");
  assert.strictEqual(data.verifiedAt, null);
  assert.strictEqual(data.districtName, null);
});

test("saveDeliveryAddress: buildingNoOverride is used with source='customer' "
  + "when the provider has no street_number (§6 provenance)", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-incomplete",
      label: "Ev",
      apartmentNo: "1",
      buildingNoOverride: "15",
    },
    idToken,
  );
  const addressId = body.result?.addressId as string;
  const doc = await getFirestore().collection("customerAddresses").doc(addressId).get();
  const data = doc.data()!;
  assert.strictEqual(data.buildingNo, "15");
  assert.strictEqual(data.buildingNoSource, "customer");
});

test("saveDeliveryAddress: an addressId owned by a different uid is rejected "
  + "(ownership check)", async () => {
  const owner = await signUpAnonymously();
  const ownerResult = await callCallable(
    fn("saveDeliveryAddress"),
    { placeId: "emulator-fixture-besiktas", label: "Ev", apartmentNo: "4" },
    owner.idToken,
  );
  const addressId = ownerResult.body.result?.addressId as string;

  const stranger = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    { addressId, placeId: "emulator-fixture-besiktas", label: "Ev", apartmentNo: "9" },
    stranger.idToken,
  );
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("saveDeliveryAddress: isDefault is mutually exclusive across a "
  + "customer's own addresses", async () => {
  const { idToken, uid } = await signUpAnonymously();
  const first = await callCallable(
    fn("saveDeliveryAddress"),
    { placeId: "emulator-fixture-besiktas", label: "Ev", apartmentNo: "1", isDefault: true },
    idToken,
  );
  const firstId = first.body.result?.addressId as string;

  const second = await callCallable(
    fn("saveDeliveryAddress"),
    { placeId: "emulator-fixture-besiktas", label: "İş", apartmentNo: "2", isDefault: true },
    idToken,
  );
  const secondId = second.body.result?.addressId as string;

  const db = getFirestore();
  const firstDoc = await db.collection("customerAddresses").doc(firstId).get();
  const secondDoc = await db.collection("customerAddresses").doc(secondId).get();
  assert.strictEqual(firstDoc.data()?.isDefault, false);
  assert.strictEqual(secondDoc.data()?.isDefault, true);
  assert.strictEqual(firstDoc.data()?.uid, uid);
});
