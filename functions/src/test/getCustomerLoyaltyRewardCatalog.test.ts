import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { LOYALTY_REWARD_CATALOG_COLLECTION } from "../loyaltyRewardCatalog";

/**
 * Emulator-backed tests for `getCustomerLoyaltyRewardCatalog` — Boncuk
 * Loyalty Program P7-B (2026-08-24). Mirrors
 * `getCustomerLoyaltySnapshot.test.ts`'s exact pattern (raw HTTP against
 * the callable-functions wire protocol, real Firestore fixtures via the
 * Admin SDK, real phone-auth via the Auth emulator).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const CATALOG_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/getCustomerLoyaltyRewardCatalog`;
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
    result?: { rewards: Record<string, unknown>[] };
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

async function createAnonymousUser(): Promise<{ idToken: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string };
  return { idToken: body.idToken };
}

const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;

async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }) },
  );
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }) },
  );
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}

const db = () => admin.firestore();

async function seedTenantMembership(uid: string, organizationId: string) {
  await db()
    .collection("tenantCustomers")
    .doc(`${organizationId}_${uid}`)
    .set({ organizationId, uid, createdAt: admin.firestore.Timestamp.now() });
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedReward(
  rewardId: string,
  overrides: {
    active?: boolean;
    archived?: boolean;
    validFrom?: admin.firestore.Timestamp | null;
    validUntil?: admin.firestore.Timestamp | null;
    sortOrder?: number;
    organizationId?: string;
    eligibleChannels?: string[];
  } = {},
) {
  const now = admin.firestore.Timestamp.now();
  await db()
    .collection(LOYALTY_REWARD_CATALOG_COLLECTION)
    .doc(rewardId)
    .set({
      rewardId,
      organizationId: overrides.organizationId ?? SINGLE_TENANT_ORGANIZATION_ID,
      title: `Test Reward ${rewardId}`,
      description: "Bir test ödülü.",
      rewardType: "explicitProductSet",
      eligibleProductIds: ["prod_test"],
      eligibleChannels: overrides.eligibleChannels ?? [
        "dineIn",
        "takeaway",
        "delivery",
        "reservationPreorder",
      ],
      boncukCost: 123,
      active: overrides.active ?? true,
      archived: overrides.archived ?? false,
      sortOrder: overrides.sortOrder ?? 0,
      version: 1,
      validFrom: overrides.validFrom ?? null,
      validUntil: overrides.validUntil ?? null,
      createdAt: now,
      updatedAt: now,
    });
}

function findReward(rewards: Record<string, unknown>[], rewardId: string) {
  return rewards.find((r) => r.rewardId === rewardId);
}

// =========================================================================
// A. Authentication / real-customer / tenant-membership gating
// =========================================================================

test("a guest (unauthenticated caller) is rejected", async () => {
  const { httpStatus, body } = await callCallable(CATALOG_URL, {});
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("an anonymous (non-phone) authenticated user is rejected", async () => {
  const { idToken } = await createAnonymousUser();
  const { httpStatus, body } = await callCallable(CATALOG_URL, {}, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("a real phone customer with no tenantCustomers membership is denied", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(CATALOG_URL, {}, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("a customer with membership only in a different organization is still denied for the canonical org — cross-tenant isolation (this app is single-tenant, so 'a different org's rewards are excluded' is not observable directly; the real behavior is a flat denial, mirroring getCustomerLoyaltySnapshot's own identical precedent)", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid, "org-2");

  const { httpStatus, body } = await callCallable(CATALOG_URL, {}, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =========================================================================
// B. Visibility filtering — active / archived / validity window
// =========================================================================

test("an inactive reward is never returned", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid, SINGLE_TENANT_ORGANIZATION_ID);
  const rewardId = nextId("reward");
  await seedReward(rewardId, { active: false });

  const { httpStatus, body } = await callCallable(CATALOG_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(findReward(body.result!.rewards, rewardId), undefined);
});

test("an archived reward is never returned", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid, SINGLE_TENANT_ORGANIZATION_ID);
  const rewardId = nextId("reward");
  await seedReward(rewardId, { archived: true });

  const { httpStatus, body } = await callCallable(CATALOG_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(findReward(body.result!.rewards, rewardId), undefined);
});

test("a reward whose validFrom is in the future is never returned", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid, SINGLE_TENANT_ORGANIZATION_ID);
  const rewardId = nextId("reward");
  const farFuture = admin.firestore.Timestamp.fromMillis(Date.now() + 365 * 24 * 60 * 60 * 1000);
  await seedReward(rewardId, { validFrom: farFuture });

  const { httpStatus, body } = await callCallable(CATALOG_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(findReward(body.result!.rewards, rewardId), undefined);
});

test("a reward whose validUntil has already passed is never returned", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid, SINGLE_TENANT_ORGANIZATION_ID);
  const rewardId = nextId("reward");
  const past = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
  await seedReward(rewardId, { validUntil: past });

  const { httpStatus, body } = await callCallable(CATALOG_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(findReward(body.result!.rewards, rewardId), undefined);
});

test("a currently valid reward IS returned, as a sanitized DTO with no internal/audit fields", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid, SINGLE_TENANT_ORGANIZATION_ID);
  const rewardId = nextId("reward");
  await seedReward(rewardId);

  const { httpStatus, body } = await callCallable(CATALOG_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  const found = findReward(body.result!.rewards, rewardId);
  assert.notStrictEqual(found, undefined);
  assert.deepStrictEqual(found, {
    rewardId,
    title: `Test Reward ${rewardId}`,
    description: "Bir test ödülü.",
    rewardType: "explicitProductSet",
    eligibleProductIds: ["prod_test"],
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: 123,
    sortOrder: 0,
    version: 1,
  });
  assert.strictEqual("organizationId" in found!, false);
  assert.strictEqual("active" in found!, false);
  assert.strictEqual("archived" in found!, false);
  assert.strictEqual("validFrom" in found!, false);
  assert.strictEqual("validUntil" in found!, false);
  assert.strictEqual("createdAt" in found!, false);
  assert.strictEqual("updatedAt" in found!, false);
});

test("P7-C.1: the sanitized DTO carries the reward's real eligibleChannels, never a hardcoded default — a narrower channel set round-trips exactly", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid, SINGLE_TENANT_ORGANIZATION_ID);
  const rewardId = nextId("reward");
  await seedReward(rewardId, { eligibleChannels: ["delivery"] });

  const { httpStatus, body } = await callCallable(CATALOG_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  const found = findReward(body.result!.rewards, rewardId);
  assert.deepStrictEqual(found?.eligibleChannels, ["delivery"]);
});

test("results are sorted by sortOrder", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid, SINGLE_TENANT_ORGANIZATION_ID);
  const rewardIdHigh = nextId("reward");
  const rewardIdLow = nextId("reward");
  // Written high-sortOrder first, low-sortOrder second — the response must
  // reorder them regardless of write/id order.
  await seedReward(rewardIdHigh, { sortOrder: 50 });
  await seedReward(rewardIdLow, { sortOrder: 1 });

  const { httpStatus, body } = await callCallable(CATALOG_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  const rewards = body.result!.rewards;
  const lowIndex = rewards.findIndex((r) => r.rewardId === rewardIdLow);
  const highIndex = rewards.findIndex((r) => r.rewardId === rewardIdHigh);
  assert.ok(lowIndex >= 0 && highIndex >= 0);
  assert.ok(lowIndex < highIndex, "the lower sortOrder reward must appear before the higher one");
});
