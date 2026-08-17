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

// Paket Servis P.3 §D14 — the "Adres Ara" root cause: this fixture used to
// return the identical Beşiktaş suggestion for every query, so no search
// could ever surface (or select) a genuinely different result.
test(
  "searchAddressAutocomplete: two materially different queries return two different, " +
    "independent suggestions — never collapsing onto the same placeId",
  async () => {
    const { idToken } = await signUpAnonymously();

    const besiktasResponse = await callCallable(
      fn("searchAddressAutocomplete"),
      { input: "Barbaros Bulvarı", sessionToken: "session-1" },
      idToken,
    );
    const kadikoyResponse = await callCallable(
      fn("searchAddressAutocomplete"),
      { input: "Kadıköy", sessionToken: "session-2" },
      idToken,
    );

    const besiktasSuggestions = besiktasResponse.body.result?.suggestions as { placeId: string; text: string }[];
    const kadikoySuggestions = kadikoyResponse.body.result?.suggestions as { placeId: string; text: string }[];

    assert.strictEqual(besiktasSuggestions[0].placeId, "emulator-fixture-besiktas");
    assert.strictEqual(kadikoySuggestions[0].placeId, "emulator-fixture-kadikoy");
    assert.notStrictEqual(besiktasSuggestions[0].text, kadikoySuggestions[0].text);
  },
);

test(
  "searchAddressAutocomplete -> resolveAddressPlace: selecting the second query's result " +
    "resolves to genuinely different coordinates than the first",
  async () => {
    const { idToken } = await signUpAnonymously();

    const autocomplete = await callCallable(
      fn("searchAddressAutocomplete"),
      { input: "Kadıköy", sessionToken: "session-3" },
      idToken,
    );
    const suggestions = autocomplete.body.result?.suggestions as { placeId: string; text: string }[];
    const resolved = await callCallable(
      fn("resolveAddressPlace"),
      { placeId: suggestions[0].placeId, sessionToken: "session-3" },
      idToken,
    );
    const place = resolved.body.result?.resolved as Record<string, unknown>;

    assert.strictEqual(place.districtName, "Kadıköy");
    assert.notStrictEqual(place.latitude, 41.0449616);
    assert.notStrictEqual(place.longitude, 29.0076831);
  },
);

// Paket Servis P.3 §D15 — the properly-fixed fixture: a full neighborhood
// vocabulary, never silently defaulting an unmatched query to Balmumcu.
async function autocompleteFirstPlaceId(idToken: string, input: string, sessionToken: string): Promise<string> {
  const { body } = await callCallable(fn("searchAddressAutocomplete"), { input, sessionToken }, idToken);
  const suggestions = body.result?.suggestions as { placeId: string; text: string }[];
  return suggestions[0]?.placeId ?? "";
}

test('searchAddressAutocomplete: "Ortaköy" and "Nişantaşı" do not return the same Balmumcu result', async () => {
  const { idToken } = await signUpAnonymously();
  const ortakoy = await autocompleteFirstPlaceId(idToken, "Ortaköy", "s-ortakoy");
  const nisantasi = await autocompleteFirstPlaceId(idToken, "Nişantaşı", "s-nisantasi");

  assert.strictEqual(ortakoy, "emulator-fixture-ortakoy");
  assert.strictEqual(nisantasi, "emulator-fixture-nisantasi");
  assert.notStrictEqual(ortakoy, "emulator-fixture-besiktas");
  assert.notStrictEqual(nisantasi, "emulator-fixture-besiktas");
});

test('searchAddressAutocomplete: "Levent" and "Maslak" produce independent results', async () => {
  const { idToken } = await signUpAnonymously();
  const levent = await autocompleteFirstPlaceId(idToken, "Levent", "s-levent");
  const maslak = await autocompleteFirstPlaceId(idToken, "Maslak", "s-maslak");

  assert.strictEqual(levent, "emulator-fixture-levent");
  assert.strictEqual(maslak, "emulator-fixture-maslak");
  assert.notStrictEqual(levent, maslak);
});

test("searchAddressAutocomplete: an unmatched, unknown query returns no suggestions — never a silent Balmumcu fallback", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("searchAddressAutocomplete"),
    { input: "zzzqqqxyz not a real place", sessionToken: "s-unknown" },
    idToken,
  );
  assert.deepStrictEqual(body.result?.suggestions, []);
});

test("searchAddressAutocomplete: every locked delivery-district neighborhood plus the deliberately out-of-service Kadıköy resolves independently", async () => {
  const { idToken } = await signUpAnonymously();
  const queries = [
    "Beşiktaş",
    "Şişli",
    "Taksim",
    "Beyoğlu",
    "Kağıthane",
    "Sarıyer",
    "Etiler",
    "Kadıköy",
  ];
  const placeIds = new Set<string>();
  for (const query of queries) {
    const placeId = await autocompleteFirstPlaceId(idToken, query, `s-${query}`);
    assert.ok(placeId.length > 0, `expected a result for "${query}"`);
    placeIds.add(placeId);
  }
  assert.strictEqual(placeIds.size, queries.length, "every neighborhood query must resolve to its own distinct placeId");
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

// ---------------------------------------------------------------------
// saveDeliveryAddress — FRAUD-F.1 address-save evidence integration
// ---------------------------------------------------------------------

async function fraudEvidenceForSavedAddress(savedAddressId: string) {
  const snapshot = await getFirestore()
    .collection("fraudEvidence")
    .where("savedAddressId", "==", savedAddressId)
    .get();
  assert.strictEqual(snapshot.docs.length, 1, "exactly one FraudEvidence must exist for this saved address");
  return snapshot.docs[0].data();
}

test("saveDeliveryAddress: a device location candidate produces an addressSave FraudEvidence with an all-null pre-order tenant anchor", async () => {
  const { idToken, uid } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-besiktas",
      label: "Ev",
      apartmentNo: "4",
      deviceLocationCandidate: {
        status: "available",
        latitude: 41.05,
        longitude: 29.01,
        accuracyMeters: 15,
        clientCapturedAt: "2026-08-15T09:00:00.000Z",
        mockLocationStatus: "notDetected",
        permissionState: "granted",
        precisionState: "precise",
      },
    },
    idToken,
  );
  const addressId = body.result?.addressId as string;

  const evidence = await fraudEvidenceForSavedAddress(addressId);
  assert.strictEqual(evidence.kind, "addressSave");
  assert.strictEqual(evidence.subjectUid, uid);
  assert.strictEqual(evidence.savedAddressId, addressId);
  assert.strictEqual(evidence.organizationId, null);
  assert.strictEqual(evidence.branchId, null);
  assert.strictEqual(evidence.orderId, null);
  assert.strictEqual(evidence.availability, "available");
});

test("saveDeliveryAddress: the authenticated caller's real uid is authoritative — a spoofed subjectUid in the payload is ignored", async () => {
  const { idToken, uid } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-besiktas",
      label: "Ev",
      apartmentNo: "4",
      subjectUid: "someone-else",
      uid: "someone-else",
      deviceLocationCandidate: {
        status: "available",
        latitude: 41.05,
        longitude: 29.01,
        accuracyMeters: 15,
        clientCapturedAt: "2026-08-15T09:00:00.000Z",
        mockLocationStatus: "unsupported",
        permissionState: "granted",
        precisionState: "unknown",
      },
    },
    idToken,
  );
  const addressId = body.result?.addressId as string;
  const evidence = await fraudEvidenceForSavedAddress(addressId);
  assert.strictEqual(evidence.subjectUid, uid);
});

test("saveDeliveryAddress: distanceMeters is derived server-side; a client-supplied distanceMeters/riskScore is ignored entirely", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-besiktas", // resolves to 41.0449616, 29.0076831
      label: "Ev",
      apartmentNo: "4",
      // Forged fields at every level a malicious client might try —
      // none of these are ever read anywhere in this call.
      distanceMeters: 0,
      riskScore: 0,
      riskLevel: "none",
      deviceLocationCandidate: {
        status: "available",
        latitude: 41.0449616,
        longitude: 29.1076831, // ~8km east of the selected address
        accuracyMeters: 15,
        clientCapturedAt: "2026-08-15T09:00:00.000Z",
        mockLocationStatus: "notDetected",
        permissionState: "granted",
        precisionState: "precise",
        distanceMeters: 999999, // forged inside the candidate itself too
        riskScore: 0,
      },
    },
    idToken,
  );
  const addressId = body.result?.addressId as string;
  const evidence = await fraudEvidenceForSavedAddress(addressId);
  const distance = evidence.interpretation?.distanceMeters as number;
  assert.ok(distance > 5000 && distance < 12000, `expected a real computed distance around 8km, got ${distance}`);
});

test("saveDeliveryAddress: App Check state is sourced only from request context, never from a client-supplied field", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-besiktas",
      label: "Ev",
      apartmentNo: "4",
      appCheckState: "VERIFIED",
      attestationState: "PASSED",
      trustedDevice: true,
      deviceLocationCandidate: {
        status: "available",
        latitude: 41.05,
        longitude: 29.01,
        accuracyMeters: 15,
        clientCapturedAt: "2026-08-15T09:00:00.000Z",
        mockLocationStatus: "notDetected",
        permissionState: "granted",
        precisionState: "precise",
      },
    },
    idToken,
  );
  const addressId = body.result?.addressId as string;
  const evidence = await fraudEvidenceForSavedAddress(addressId);
  // No real App Check token is ever sent by this raw-HTTP test harness —
  // this proves the value reflects the real (absent) request context,
  // never the forged "VERIFIED" the payload tried to assert.
  assert.strictEqual(evidence.interpretation?.appCheckState, "MISSING");
});

test("saveDeliveryAddress: server timestamps (serverReceivedAt/createdAt) are present and authoritative; clientCapturedAt remains explicitly separate client provenance", async () => {
  const { idToken } = await signUpAnonymously();
  const skewedClientTimestamp = "2020-01-01T00:00:00.000Z"; // deliberately absurd
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-besiktas",
      label: "Ev",
      apartmentNo: "4",
      deviceLocationCandidate: {
        status: "available",
        latitude: 41.05,
        longitude: 29.01,
        accuracyMeters: 15,
        clientCapturedAt: skewedClientTimestamp,
        mockLocationStatus: "notDetected",
        permissionState: "granted",
        precisionState: "precise",
      },
    },
    idToken,
  );
  const addressId = body.result?.addressId as string;
  const evidence = await fraudEvidenceForSavedAddress(addressId);

  assert.ok(typeof evidence.serverReceivedAt === "string" && evidence.serverReceivedAt.length > 0);
  assert.ok(typeof evidence.createdAt === "string" && evidence.createdAt.length > 0);
  assert.notStrictEqual(evidence.serverReceivedAt, skewedClientTimestamp);
  // The skewed value is preserved exactly as reported, never silently
  // reconciled against the real server time.
  assert.strictEqual(evidence.clientLocation?.clientCapturedAt, skewedClientTimestamp);
});

test("saveDeliveryAddress: the device location is reverse-geocoded server-side, independently of the selected address's own resolution", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-incomplete", // selected address has NO district
      label: "Ev",
      apartmentNo: "4",
      deviceLocationCandidate: {
        status: "available",
        latitude: 41.05, // resolves via the emulator-safe fixture to emulator-fixture-besiktas
        longitude: 29.01,
        accuracyMeters: 15,
        clientCapturedAt: "2026-08-15T09:00:00.000Z",
        mockLocationStatus: "notDetected",
        permissionState: "granted",
        precisionState: "precise",
      },
    },
    idToken,
  );
  const addressId = body.result?.addressId as string;
  const evidence = await fraudEvidenceForSavedAddress(addressId);

  // The DEVICE point resolves to the Beşiktaş fixture even though the
  // SELECTED address (emulator-fixture-incomplete) has no district at
  // all — proves these are two fully independent resolutions.
  assert.strictEqual(evidence.interpretation?.district, "Beşiktaş");
  assert.strictEqual(evidence.interpretation?.buildingNumber, "74");
});

test("saveDeliveryAddress: reverse-geocode failure for the device point never fabricates fields — coordinates/accuracy evidence remains valid, derived fields stay null", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-besiktas",
      label: "Ev",
      apartmentNo: "4",
      deviceLocationCandidate: {
        status: "available",
        latitude: 0,
        longitude: 0, // the emulator-safe reverse-geocode sentinel for "unresolvable"
        accuracyMeters: 999,
        clientCapturedAt: "2026-08-15T09:00:00.000Z",
        mockLocationStatus: "unavailable",
        permissionState: "granted",
        precisionState: "reduced",
      },
    },
    idToken,
  );
  const addressId = body.result?.addressId as string;
  const evidence = await fraudEvidenceForSavedAddress(addressId);

  assert.strictEqual(evidence.availability, "available");
  assert.strictEqual(evidence.clientLocation?.latitude, 0);
  assert.strictEqual(evidence.clientLocation?.longitude, 0);
  assert.strictEqual(evidence.clientLocation?.accuracyMeters, 999);
  assert.strictEqual(evidence.interpretation?.buildingNumber ?? null, null);
  assert.strictEqual(evidence.interpretation?.district ?? null, null);
});

test("saveDeliveryAddress: no device location candidate at all still saves the address, and records unavailable evidence — coordinates are never fabricated", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    { placeId: "emulator-fixture-besiktas", label: "Ev", apartmentNo: "4" },
    idToken,
  );
  assert.strictEqual(body.error, undefined, "address save must succeed even with no candidate at all");
  const addressId = body.result?.addressId as string;
  const evidence = await fraudEvidenceForSavedAddress(addressId);

  assert.strictEqual(evidence.availability, "unavailable");
  assert.strictEqual(evidence.clientLocation, null);
});

test("saveDeliveryAddress: an explicit unavailable candidate (permission denied) still saves the address and records the reason", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-besiktas",
      label: "Ev",
      apartmentNo: "4",
      deviceLocationCandidate: { status: "unavailable", unavailableReason: "permission_denied" },
    },
    idToken,
  );
  assert.strictEqual(body.result?.verificationStatus, "verified", "address save proceeds unaffected");
  const addressId = body.result?.addressId as string;
  const evidence = await fraudEvidenceForSavedAddress(addressId);

  assert.strictEqual(evidence.availability, "unavailable");
  assert.strictEqual(evidence.unavailableReason, "permission_denied");
  assert.strictEqual(evidence.clientLocation, null);
});

test("saveDeliveryAddress: a malformed device location candidate (missing accuracyMeters) is recorded as incomplete, address save unaffected", async () => {
  const { idToken } = await signUpAnonymously();
  const { body } = await callCallable(
    fn("saveDeliveryAddress"),
    {
      placeId: "emulator-fixture-besiktas",
      label: "Ev",
      apartmentNo: "4",
      deviceLocationCandidate: {
        status: "available",
        latitude: 41.05,
        longitude: 29.01,
        // accuracyMeters deliberately omitted
        clientCapturedAt: "2026-08-15T09:00:00.000Z",
      },
    },
    idToken,
  );
  assert.strictEqual(body.result?.verificationStatus, "verified");
  const addressId = body.result?.addressId as string;
  const evidence = await fraudEvidenceForSavedAddress(addressId);

  assert.strictEqual(evidence.availability, "incomplete");
  assert.strictEqual(evidence.clientLocation, null);
});
