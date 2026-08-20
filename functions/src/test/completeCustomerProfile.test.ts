import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `completeCustomerProfile` — Customer
 * Registration CR.1. Mirrors `customerPhotoUploadGrants.test.ts`'s exact
 * pattern (raw HTTP against the callable-functions wire protocol, real
 * Firestore fixtures via the Admin SDK, real phone-auth via the Auth
 * emulator).
 *
 * **Honest, disclosed scope limitation**: "missing phone claim denied" is
 * not covered here as a separate emulator-integration test. The Auth
 * emulator's real phone sign-in flow always populates `phone_number`
 * whenever `firebase.sign_in_provider` is `"phone"` — that specific
 * combination (phone provider, no phone claim) cannot be produced through
 * a genuine sign-in, and `firebase` is a reserved custom-claims namespace
 * (`setCustomUserClaims` rejects it), so it cannot be spoofed via a custom
 * token either. The guard itself remains in `completeCustomerProfile.ts`
 * as defensive code; it is exercised implicitly by every other test here
 * never tripping it, not by a dedicated case.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const COMPLETE_PROFILE_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/completeCustomerProfile`;
const SINGLE_TENANT_ORGANIZATION_ID = "org-1";

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

async function createAnonymousUser(): Promise<{ idToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; localId: string };
  return { idToken: body.idToken, uid: body.localId };
}

const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;

async function createRealPhoneUser(): Promise<{ idToken: string; uid: string; phoneNumber: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }),
    },
  );
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }),
    },
  );
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId, phoneNumber };
}

const db = () => admin.firestore();

function validRequest(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    firstName: "Ayşe",
    lastName: "Yılmaz",
    email: "ayse.yilmaz@example.com",
    occupationStatus: "working",
    workplaceName: "Abaküs Kahve",
    gender: "female",
    birthDate: "1990-08-20",
    ...overrides,
  };
}

async function customerDoc(uid: string) {
  return (await db().collection("customers").doc(uid).get()).data();
}

async function membershipDoc(uid: string, organizationId: string = SINGLE_TENANT_ORGANIZATION_ID) {
  return (await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).get()).data();
}

// =========================================================================
// A. Authentication / real-customer gating
// =========================================================================

test("a guest (unauthenticated caller) is rejected", async () => {
  const { httpStatus, body } = await callCallable(COMPLETE_PROFILE_URL, validRequest());
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("an anonymous (non-phone) authenticated user is rejected — not a real customer", async () => {
  const { idToken } = await createAnonymousUser();
  const { httpStatus, body } = await callCallable(COMPLETE_PROFILE_URL, validRequest(), idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("a request with no App Check token still succeeds under the emulator — matches this codebase's shared appCheckConfig policy", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(COMPLETE_PROFILE_URL, validRequest(), idToken);
  assert.strictEqual(httpStatus, 200);
  void uid;
});

// =========================================================================
// B. Field validation
// =========================================================================

test("missing firstName is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ firstName: undefined }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("blank-only firstName is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ firstName: "   " }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("missing lastName is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ lastName: "" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("an invalid email format is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ email: "not-an-email" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("email is trimmed and lowercased before being stored", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ email: "  Ayse.Yilmaz@EXAMPLE.com  " }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const data = await customerDoc(uid);
  assert.strictEqual(data?.email, "ayse.yilmaz@example.com");
});

test("an invalid occupationStatus is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ occupationStatus: "retired" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("an invalid gender is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ gender: "other" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("gender: preferNotToSay is a fully valid, first-class choice", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ gender: "preferNotToSay" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const data = await customerDoc(uid);
  assert.strictEqual(data?.gender, "preferNotToSay");
});

// -------------------------------------------------------------------------
// B.1 — CR.1.1: birthDate validation
// -------------------------------------------------------------------------

test("missing birthDate is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ birthDate: undefined }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("a malformed (locale-formatted) birthDate is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ birthDate: "20/08/1990" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("a calendar-impossible birthDate (Feb 30) is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ birthDate: "2024-02-30" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("a future birthDate is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const futureYear = new Date().getUTCFullYear() + 1;
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ birthDate: `${futureYear}-01-01` }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("a birthDate before the earliest accepted year is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ birthDate: "1899-12-31" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("a valid birthDate is accepted and stored exactly as the canonical YYYY-MM-DD value submitted", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ birthDate: "1990-08-20" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const data = await customerDoc(uid);
  assert.strictEqual(data?.birthDate, "1990-08-20");
});

test("occupationStatus working without workplaceName is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ occupationStatus: "working", workplaceName: undefined }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("occupationStatus student without educationalInstitutionName is rejected as invalid-argument", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ occupationStatus: "student", workplaceName: undefined }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("occupationStatus student accepts a non-university institution (high school), never labeled university-only", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({
      occupationStatus: "student",
      workplaceName: undefined,
      educationalInstitutionName: "Kabataş Erkek Lisesi",
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const data = await customerDoc(uid);
  assert.strictEqual(data?.educationalInstitutionName, "Kabataş Erkek Lisesi");
  assert.strictEqual(data?.workplaceName, null);
});

test("occupationStatus other clears/never persists workplaceName or educationalInstitutionName even if the client sends them", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({
      occupationStatus: "other",
      workplaceName: "should never be stored",
      educationalInstitutionName: "should never be stored either",
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const data = await customerDoc(uid);
  assert.strictEqual(data?.workplaceName, null);
  assert.strictEqual(data?.educationalInstitutionName, null);
  assert.strictEqual(data?.occupationStatus, "other");
});

// =========================================================================
// C. Server-authoritative identity — never trust the client
// =========================================================================

test("a client-supplied organizationId can never choose the tenant — always resolved server-side to the single-tenant constant", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ organizationId: "some-other-tenant-the-client-tried-to-join" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.organizationId, SINGLE_TENANT_ORGANIZATION_ID);

  const forged = await membershipDoc(uid, "some-other-tenant-the-client-tried-to-join");
  assert.strictEqual(forged, undefined, "no membership was ever created under the client-chosen tenant");
  const real = await membershipDoc(uid);
  assert.ok(real, "membership was created under the server-resolved single tenant instead");
});

test("a client-supplied phoneNumber can never override the verified auth phone", async () => {
  const { idToken, uid, phoneNumber } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ phoneNumber: "+905559998877" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const data = await customerDoc(uid);
  assert.strictEqual(data?.phoneNumber, phoneNumber);
});

test("a client-supplied accountStatus/role-like field is never read or persisted", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ accountStatus: "admin", roles: ["owner"], organizationAccess: ["org-1"] }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const data = await customerDoc(uid);
  assert.strictEqual(data?.accountStatus, "active");
  assert.strictEqual(data?.roles, undefined);
  assert.strictEqual(data?.organizationAccess, undefined);
});

test("no custom auth claims are ever set by this callable — no privileged role path is introduced", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(COMPLETE_PROFILE_URL, validRequest(), idToken);
  assert.strictEqual(httpStatus, 200);
  const userRecord = await admin.auth().getUser(uid);
  assert.deepStrictEqual(userRecord.customClaims ?? {}, {});
  const membership = await membershipDoc(uid);
  assert.deepStrictEqual(Object.keys(membership ?? {}).sort(), ["createdAt", "organizationId", "uid"]);
});

// =========================================================================
// D. Canonical document creation / displayName derivation
// =========================================================================

test("a first-time, valid request creates BOTH customers/{uid} and tenantCustomers/{orgId}_{uid} atomically", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(COMPLETE_PROFILE_URL, validRequest(), idToken);

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.alreadyCompleted, false);

  const customer = await customerDoc(uid);
  assert.strictEqual(customer?.uid, uid);
  assert.strictEqual(customer?.firstName, "Ayşe");
  assert.strictEqual(customer?.lastName, "Yılmaz");
  assert.strictEqual(customer?.displayName, "Ayşe Yılmaz");
  assert.strictEqual(customer?.email, "ayse.yilmaz@example.com");
  assert.strictEqual(customer?.occupationStatus, "working");
  assert.strictEqual(customer?.workplaceName, "Abaküs Kahve");
  assert.strictEqual(customer?.educationalInstitutionName, null);
  assert.strictEqual(customer?.gender, "female");
  assert.strictEqual(customer?.accountStatus, "active");
  assert.ok(customer?.profileCompletedAt, "profileCompletedAt is set");
  assert.ok(customer?.createdAt);
  assert.ok(customer?.updatedAt);

  const membership = await membershipDoc(uid);
  assert.strictEqual(membership?.organizationId, SINGLE_TENANT_ORGANIZATION_ID);
  assert.strictEqual(membership?.uid, uid);
});

test("displayName is always server-derived from firstName+lastName — a client cannot submit its own displayName", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ displayName: "Something Else Entirely" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const data = await customerDoc(uid);
  assert.strictEqual(data?.displayName, "Ayşe Yılmaz");
});

// =========================================================================
// E. Idempotency / retry-safety / repair scenarios
// =========================================================================

test("calling twice with identical, already-complete data is idempotent — second call returns alreadyCompleted, no field changes", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const first = await callCallable(COMPLETE_PROFILE_URL, validRequest(), idToken);
  assert.strictEqual(first.body.result?.alreadyCompleted, false);
  const firstData = await customerDoc(uid);

  const second = await callCallable(COMPLETE_PROFILE_URL, validRequest(), idToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.alreadyCompleted, true);
  const secondData = await customerDoc(uid);
  assert.deepStrictEqual(secondData, firstData, "no field was touched by the idempotent repeat call");
});

test("an already-complete customer is never destructively overwritten by a repeat call with different values", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await callCallable(COMPLETE_PROFILE_URL, validRequest({ firstName: "Original" }), idToken);

  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ firstName: "Attempted Overwrite" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.alreadyCompleted, true);

  const data = await customerDoc(uid);
  assert.strictEqual(data?.firstName, "Original", "this bootstrap endpoint never doubles as a profile-edit endpoint");
});

test("scenario B — customer already complete but tenant membership missing: only the membership is repaired, the customer record is untouched", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const now = admin.firestore.Timestamp.now();
  await db().collection("customers").doc(uid).set({
    uid,
    firstName: "Zeynep",
    lastName: "Kaya",
    displayName: "Zeynep Kaya",
    email: "zeynep@example.com",
    phoneNumber: "+15559990000",
    accountStatus: "active",
    occupationStatus: "other",
    workplaceName: null,
    educationalInstitutionName: null,
    gender: "female",
    birthDate: "1985-03-12",
    profileCompletedAt: now,
    createdAt: now,
    updatedAt: now,
  });
  // No tenantCustomers doc seeded — membership missing.

  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ birthDate: "1990-08-20" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.alreadyCompleted, false);

  const data = await customerDoc(uid);
  assert.strictEqual(data?.firstName, "Zeynep", "the already-complete customer record was never touched");
  assert.strictEqual(data?.birthDate, "1985-03-12", "birthDate was never touched by the membership-only repair");
  const membership = await membershipDoc(uid);
  assert.ok(membership, "the missing membership was created");
});

test("CR.1.1 — a repair call triggered by an unrelated missing field can never overwrite an already-set birthDate", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const now = admin.firestore.Timestamp.now();
  await db().collection("customers").doc(uid).set({
    uid,
    firstName: "Mehmet",
    lastName: "Demir",
    displayName: "Mehmet Demir",
    email: "mehmet@example.com",
    phoneNumber: "+15559990002",
    accountStatus: "active",
    occupationStatus: "other",
    workplaceName: null,
    educationalInstitutionName: null,
    birthDate: "1975-01-15",
    // gender intentionally missing/invalid — this is the field that makes
    // isProfileComplete false and triggers the (C) repair branch, even
    // though birthDate itself is already correctly set.
    profileCompletedAt: now,
    createdAt: now,
    updatedAt: now,
  });
  await db().collection("tenantCustomers").doc(`${SINGLE_TENANT_ORGANIZATION_ID}_${uid}`).set({
    organizationId: SINGLE_TENANT_ORGANIZATION_ID,
    uid,
    createdAt: now,
  });

  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({ gender: "male", birthDate: "2001-06-30" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.alreadyCompleted, false);

  const data = await customerDoc(uid);
  assert.strictEqual(data?.gender, "male", "the actually-missing field (gender) was repaired");
  assert.strictEqual(
    data?.birthDate,
    "1975-01-15",
    "the already-set birthDate was never overwritten by the resubmitted value, even during an unrelated repair",
  );
});

test("scenario C — tenant membership already exists but customer record is missing: the customer is created without duplicating membership", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await db().collection("tenantCustomers").doc(`${SINGLE_TENANT_ORGANIZATION_ID}_${uid}`).set({
    organizationId: SINGLE_TENANT_ORGANIZATION_ID,
    uid,
    createdAt: admin.firestore.Timestamp.now(),
  });
  const originalMembership = await membershipDoc(uid);

  const { httpStatus, body } = await callCallable(COMPLETE_PROFILE_URL, validRequest(), idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.alreadyCompleted, false);

  const data = await customerDoc(uid);
  assert.strictEqual(data?.firstName, "Ayşe");
  const membershipAfter = await membershipDoc(uid);
  assert.deepStrictEqual(membershipAfter, originalMembership, "the pre-existing membership doc was not rewritten");
});

test("scenario C — an incomplete customer record (missing gender/profileCompletedAt) is repaired to complete", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await db().collection("customers").doc(uid).set({
    uid,
    firstName: "Yarım",
    lastName: "Profil",
    displayName: "Yarım Profil",
    email: "yarim@example.com",
    phoneNumber: "+15559990001",
    accountStatus: "active",
    // occupationStatus/gender/profileCompletedAt intentionally missing —
    // a partial registration attempt that never finished.
    createdAt: admin.firestore.Timestamp.now(),
  });

  const { httpStatus, body } = await callCallable(COMPLETE_PROFILE_URL, validRequest(), idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.alreadyCompleted, false);

  const data = await customerDoc(uid);
  assert.strictEqual(data?.firstName, "Ayşe", "the incomplete record was repaired using the freshly submitted values");
  assert.ok(data?.profileCompletedAt);
  assert.ok(data?.gender);
  assert.strictEqual(data?.birthDate, "1990-08-20");
});

test("CR.1.1 — a legacy customer complete in every other field but missing birthDate is repaired with the freshly submitted birthDate", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const now = admin.firestore.Timestamp.now();
  await db().collection("customers").doc(uid).set({
    uid,
    firstName: "Legacy",
    lastName: "Musteri",
    displayName: "Legacy Musteri",
    email: "legacy@example.com",
    phoneNumber: "+15559990003",
    accountStatus: "active",
    occupationStatus: "other",
    workplaceName: null,
    educationalInstitutionName: null,
    gender: "male",
    // birthDate intentionally absent — a pre-CR.1.1 record.
    profileCompletedAt: now,
    createdAt: now,
    updatedAt: now,
  });
  await db().collection("tenantCustomers").doc(`${SINGLE_TENANT_ORGANIZATION_ID}_${uid}`).set({
    organizationId: SINGLE_TENANT_ORGANIZATION_ID,
    uid,
    createdAt: now,
  });

  // The repair branch always rewrites the customer patch from whatever the
  // client resubmits (pre-existing CR.1 behavior — this callable has no
  // partial-field-only update mode) — so a legacy customer redoing the
  // form naturally resubmits their own already-correct values for every
  // other field, matching the seed above. This is not a form-prefill
  // test — it isolates the one field genuinely new here: birthDate.
  const { httpStatus, body } = await callCallable(
    COMPLETE_PROFILE_URL,
    validRequest({
      firstName: "Legacy",
      lastName: "Musteri",
      email: "legacy@example.com",
      occupationStatus: "other",
      workplaceName: undefined,
      gender: "male",
      birthDate: "1990-08-20",
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.alreadyCompleted, false, "the record was incomplete solely due to the missing birthDate");

  const data = await customerDoc(uid);
  assert.strictEqual(data?.firstName, "Legacy", "no other pre-existing field's data was lost");
  assert.strictEqual(data?.gender, "male", "no other pre-existing field's data was lost");
  assert.strictEqual(data?.birthDate, "1990-08-20", "birthDate was set for the first time");
});

test("concurrent duplicate submissions for the same customer never corrupt or duplicate the canonical documents", async () => {
  const { idToken, uid } = await createRealPhoneUser();

  const results = await Promise.all(
    Array.from({ length: 5 }, () => callCallable(COMPLETE_PROFILE_URL, validRequest(), idToken)),
  );
  for (const r of results) {
    assert.strictEqual(r.httpStatus, 200, JSON.stringify(r.body));
  }

  const data = await customerDoc(uid);
  assert.strictEqual(data?.firstName, "Ayşe");
  assert.strictEqual(data?.displayName, "Ayşe Yılmaz");
  const membership = await membershipDoc(uid);
  assert.ok(membership);

  const customerCount = (
    await db().collection("customers").where("uid", "==", uid).get()
  ).size;
  assert.strictEqual(customerCount, 1, "exactly one customer document, never duplicated");
});
