import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `getCustomerLoyaltySnapshot` — Boncuk Loyalty
 * Program P1 (2026-08-20), extended P2B-B (2026-08-22) for `boncukDebt`.
 * Mirrors `completeCustomerProfile.test.ts`'s exact pattern (raw HTTP
 * against the callable-functions wire protocol, real Firestore fixtures via
 * the Admin SDK, real phone-auth via the Auth emulator).
 *
 * **Honest, disclosed scope limitation**, identical to
 * `completeCustomerProfile.test.ts`'s own: a genuinely different
 * "authenticated, non-anonymous, non-phone" identity cannot be produced
 * through a real Auth-emulator sign-in flow in this codebase's test
 * harness, and `firebase` is a reserved custom-claims namespace
 * (`setCustomUserClaims` rejects it), so it cannot be spoofed either. The
 * "anonymous/guest denied" test below already exercises the
 * `isRealCustomer` guard's `false` branch; a separate "some other
 * non-phone provider" case would require the exact same guard condition,
 * so it is not separately tested here.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SNAPSHOT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/getCustomerLoyaltySnapshot`;
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

async function seedTenantMembership(uid: string, organizationId: string = SINGLE_TENANT_ORGANIZATION_ID) {
  await db()
    .collection("tenantCustomers")
    .doc(`${organizationId}_${uid}`)
    .set({ organizationId, uid, createdAt: admin.firestore.Timestamp.now() });
}

async function accountDoc(uid: string, organizationId: string = SINGLE_TENANT_ORGANIZATION_ID) {
  return (await db().collection("loyaltyAccounts").doc(`${organizationId}_${uid}`).get()).data();
}

// =========================================================================
// A. Authentication / real-customer / tenant-membership gating
// =========================================================================

test("a guest (unauthenticated caller) is rejected", async () => {
  const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {});
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("an anonymous (non-phone) authenticated user is rejected — not a real customer", async () => {
  const { idToken } = await createAnonymousUser();
  const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {}, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("a real phone customer with no tenantCustomers membership is denied", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {}, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =========================================================================
// B. Zero-account provisioning
// =========================================================================

test("a real phone customer with membership provisions a zero account", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);

  const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result, {
    spendableBalance: 0,
    boncukDebt: 0,
    earningRemainderMinorUnits: 0,
    lifetimeEarned: 0,
    lifetimeRedeemed: 0,
  });

  const data = await accountDoc(uid);
  assert.strictEqual(data?.organizationId, SINGLE_TENANT_ORGANIZATION_ID);
  assert.strictEqual(data?.customerId, uid);
  assert.strictEqual(data?.spendableBalance, 0);
  assert.strictEqual(data?.boncukDebt, 0);
  assert.strictEqual(data?.orderEligibleNetSpendMinorUnits, 0);
  assert.strictEqual(data?.earningRemainderMinorUnits, 0);
  assert.strictEqual(data?.lifetimeEarned, 0);
  assert.strictEqual(data?.lifetimeRedeemed, 0);
  assert.strictEqual(data?.revision, 1);
  assert.ok(data?.createdAt);
  assert.ok(data?.updatedAt);
});

test("the account document id is exactly {organizationId}_{uid}", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  await callCallable(SNAPSHOT_URL, {}, idToken);

  const snap = await db().collection("loyaltyAccounts").doc(`${SINGLE_TENANT_ORGANIZATION_ID}_${uid}`).get();
  assert.strictEqual(snap.exists, true);
});

test("organizationId always resolves to the canonical single-tenant constant, regardless of any client-sent data — proves organizationId can never be overridden by the client", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);

  const { httpStatus } = await callCallable(SNAPSHOT_URL, { organizationId: "org-evil" }, idToken);
  assert.strictEqual(httpStatus, 200);

  const data = await accountDoc(uid);
  assert.strictEqual(data?.organizationId, SINGLE_TENANT_ORGANIZATION_ID);
  // Confirm no account was ever created under the attempted org.
  const evilSnap = await db().collection("loyaltyAccounts").doc(`org-evil_${uid}`).get();
  assert.strictEqual(evilSnap.exists, false);
});

test("a customer with membership only in a different organization is still denied for the canonical org — cannot provision another tenant's account by any means available to the client", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  // Membership seeded under a DIFFERENT org than the canonical one this
  // callable resolves — the callable has no client-facing way to target
  // that other org at all, so it must still deny for the canonical org.
  await seedTenantMembership(uid, "org-2");

  const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {}, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =========================================================================
// C. Idempotency — never resets existing state
// =========================================================================

test("repeated provisioning calls are idempotent — same values, no duplicate document, revision unchanged", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);

  const first = await callCallable(SNAPSHOT_URL, {}, idToken);
  const second = await callCallable(SNAPSHOT_URL, {}, idToken);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(second.httpStatus, 200);
  assert.deepStrictEqual(first.body.result, second.body.result);

  const data = await accountDoc(uid);
  assert.strictEqual(data?.revision, 1);
});

test("an existing non-zero account's balance/debt/remainder/lifetime counters are NEVER reset by a snapshot call", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  const accountRef = db().collection("loyaltyAccounts").doc(`${SINGLE_TENANT_ORGANIZATION_ID}_${uid}`);
  const now = admin.firestore.Timestamp.now();
  await accountRef.set({
    organizationId: SINGLE_TENANT_ORGANIZATION_ID,
    customerId: uid,
    spendableBalance: 42,
    boncukDebt: 9,
    orderEligibleNetSpendMinorUnits: 217300,
    earningRemainderMinorUnits: 3300,
    lifetimeEarned: 100,
    lifetimeRedeemed: 58,
    createdAt: now,
    updatedAt: now,
    revision: 7,
  });

  const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result, {
    spendableBalance: 42,
    boncukDebt: 9,
    earningRemainderMinorUnits: 3300,
    lifetimeEarned: 100,
    lifetimeRedeemed: 58,
  });

  const data = await accountDoc(uid);
  assert.strictEqual(data?.spendableBalance, 42);
  assert.strictEqual(data?.boncukDebt, 9);
  assert.strictEqual(data?.orderEligibleNetSpendMinorUnits, 217300, "internal aggregate must never be touched by a read");
  assert.strictEqual(data?.earningRemainderMinorUnits, 3300);
  assert.strictEqual(data?.lifetimeEarned, 100);
  assert.strictEqual(data?.lifetimeRedeemed, 58);
  assert.strictEqual(data?.revision, 7, "a pure read must never bump revision");
});

// =========================================================================
// D. Legacy (pre-P2B) account read tolerance
// =========================================================================

test("a legacy account missing boncukDebt reads back as 0 in the response, without writing anything back to the stored document", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  const accountRef = db().collection("loyaltyAccounts").doc(`${SINGLE_TENANT_ORGANIZATION_ID}_${uid}`);
  const now = admin.firestore.Timestamp.now();
  // Deliberately the OLD (pre-P2B) shape — no boncukDebt field at all.
  await accountRef.set({
    organizationId: SINGLE_TENANT_ORGANIZATION_ID,
    customerId: uid,
    spendableBalance: 5,
    earningRemainderMinorUnits: 500,
    lifetimeEarned: 5,
    lifetimeRedeemed: 0,
    createdAt: now,
    updatedAt: now,
    revision: 1,
  });

  const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.boncukDebt, 0, "a missing boncukDebt reads as 0 for display purposes only");
  assert.strictEqual(body.result?.spendableBalance, 5);

  const data = await accountDoc(uid);
  assert.strictEqual(data && "boncukDebt" in data, false, "a pure read must never backfill/persist the missing field");
});
