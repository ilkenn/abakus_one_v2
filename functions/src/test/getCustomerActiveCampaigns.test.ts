import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { CAMPAIGNS_COLLECTION } from "../campaignEngine";

/**
 * Emulator-backed tests for `getCustomerActiveCampaigns` — Server-
 * Authoritative Campaign Engine P8-B (2026-08-25). Mirrors
 * `getCustomerLoyaltyRewardCatalog.test.ts`'s exact pattern (raw HTTP
 * against the callable-functions wire protocol, real Firestore fixtures via
 * the Admin SDK, real phone-auth via the Auth emulator) — with the one
 * deliberate difference this callable itself has: an ANONYMOUS caller is
 * allowed through (locked decision — a table guest must be able to see
 * which campaigns exist, even though `getCustomerLoyaltyRewardCatalog`
 * itself requires a real phone customer).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const CAMPAIGNS_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/getCustomerActiveCampaigns`;
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
    result?: { campaigns: Record<string, unknown>[] };
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

function istanbulWeekdayNumber(date: Date): number {
  const formatted = new Intl.DateTimeFormat("en-US", { timeZone: "Europe/Istanbul", weekday: "long" }).format(date);
  const map: Record<string, number> = {
    Sunday: 0,
    Monday: 1,
    Tuesday: 2,
    Wednesday: 3,
    Thursday: 4,
    Friday: 5,
    Saturday: 6,
  };
  return map[formatted];
}

async function seedCampaign(
  campaignId: string,
  overrides: {
    active?: boolean;
    archived?: boolean;
    organizationId?: string;
    eligibleChannels?: string[];
    schedule?: Record<string, unknown>;
    sortOrder?: number;
  } = {},
) {
  const now = admin.firestore.Timestamp.now();
  await db()
    .collection(CAMPAIGNS_COLLECTION)
    .doc(campaignId)
    .set({
      campaignId,
      organizationId: overrides.organizationId ?? SINGLE_TENANT_ORGANIZATION_ID,
      title: `Test Campaign ${campaignId}`,
      description: "Bir test kampanyası.",
      campaignType: "percentageDiscount",
      rule: { mechanic: "percentage", percentBasisPoints: 1500, scope: { kind: "order" } },
      eligibleChannels: overrides.eligibleChannels ?? ["dineIn", "takeaway", "delivery", "reservationPreorder"],
      eligibleProductIds: null,
      eligibleCategoryIds: null,
      minimumBasketMinorUnits: null,
      schedule: overrides.schedule ?? { mode: "oneTime", startAt: null, endAt: null },
      usageLimit: null,
      perCustomerUsageLimit: null,
      active: overrides.active ?? true,
      archived: overrides.archived ?? false,
      sortOrder: overrides.sortOrder ?? 0,
      version: 1,
      createdAt: now,
      updatedAt: now,
    });
}

function findCampaign(campaigns: Record<string, unknown>[], campaignId: string) {
  return campaigns.find((c) => c.campaignId === campaignId);
}

// =========================================================================
// A. Authentication — anonymous callers are allowed, unlike the Reward Catalog
// =========================================================================

test("a guest (unauthenticated caller) is rejected", async () => {
  const { httpStatus, body } = await callCallable(CAMPAIGNS_URL, {});
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("an anonymous (non-phone) authenticated user IS allowed through, sees an empty list when no campaign exists — locked decision, unlike getCustomerLoyaltyRewardCatalog", async () => {
  const { idToken } = await createAnonymousUser();
  const { httpStatus, body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result?.campaigns, []);
});

test("an anonymous caller sees a real, currently-eligible campaign — no tenantCustomers membership required for a guest", async () => {
  const { idToken } = await createAnonymousUser();
  const campaignId = nextId("camp");
  await seedCampaign(campaignId);

  const { httpStatus, body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.notStrictEqual(findCampaign(body.result!.campaigns, campaignId), undefined);
});

test("a real phone customer with no tenantCustomers membership is denied", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("a real phone customer WITH tenantCustomers membership sees a real campaign", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid, SINGLE_TENANT_ORGANIZATION_ID);
  const campaignId = nextId("camp");
  await seedCampaign(campaignId);

  const { httpStatus, body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.notStrictEqual(findCampaign(body.result!.campaigns, campaignId), undefined);
});

// =========================================================================
// B. Visibility filtering — active / archived / schedule
// =========================================================================

test("an inactive campaign is never returned", async () => {
  const { idToken } = await createAnonymousUser();
  const campaignId = nextId("camp");
  await seedCampaign(campaignId, { active: false });

  const { body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.strictEqual(findCampaign(body.result!.campaigns, campaignId), undefined);
});

test("an archived campaign is never returned", async () => {
  const { idToken } = await createAnonymousUser();
  const campaignId = nextId("camp");
  await seedCampaign(campaignId, { archived: true });

  const { body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.strictEqual(findCampaign(body.result!.campaigns, campaignId), undefined);
});

test("a oneTime campaign whose startAt is in the future is never returned", async () => {
  const { idToken } = await createAnonymousUser();
  const campaignId = nextId("camp");
  const farFuture = admin.firestore.Timestamp.fromMillis(Date.now() + 365 * 24 * 60 * 60 * 1000);
  await seedCampaign(campaignId, { schedule: { mode: "oneTime", startAt: farFuture, endAt: null } });

  const { body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.strictEqual(findCampaign(body.result!.campaigns, campaignId), undefined);
});

test("a oneTime campaign whose endAt has already passed is never returned", async () => {
  const { idToken } = await createAnonymousUser();
  const campaignId = nextId("camp");
  const past = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
  await seedCampaign(campaignId, { schedule: { mode: "oneTime", startAt: null, endAt: past } });

  const { body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.strictEqual(findCampaign(body.result!.campaigns, campaignId), undefined);
});

test("a oneTime campaign currently inside its window IS returned", async () => {
  const { idToken } = await createAnonymousUser();
  const campaignId = nextId("camp");
  const past = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
  const future = admin.firestore.Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000);
  await seedCampaign(campaignId, { schedule: { mode: "oneTime", startAt: past, endAt: future } });

  const { body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.notStrictEqual(findCampaign(body.result!.campaigns, campaignId), undefined);
});

test("a recurring campaign covering today (all-day, Europe/Istanbul) IS returned", async () => {
  const { idToken } = await createAnonymousUser();
  const campaignId = nextId("camp");
  const today = istanbulWeekdayNumber(new Date());
  await seedCampaign(campaignId, {
    schedule: { mode: "recurring", recurringWindows: [{ weekdays: [today], startTime: "00:00", endTime: "23:59" }] },
  });

  const { body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.notStrictEqual(findCampaign(body.result!.campaigns, campaignId), undefined);
});

test("a recurring campaign that deliberately excludes today (all other weekdays, all-day) is never returned", async () => {
  const { idToken } = await createAnonymousUser();
  const campaignId = nextId("camp");
  const today = istanbulWeekdayNumber(new Date());
  const otherWeekdays = [0, 1, 2, 3, 4, 5, 6].filter((d) => d !== today);
  await seedCampaign(campaignId, {
    schedule: {
      mode: "recurring",
      recurringWindows: [{ weekdays: otherWeekdays, startTime: "00:00", endTime: "23:59" }],
    },
  });

  const { body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  assert.strictEqual(findCampaign(body.result!.campaigns, campaignId), undefined);
});

// =========================================================================
// C. Sanitized DTO shape / sorting / empty-by-default
// =========================================================================

test("a currently eligible campaign is returned as a sanitized DTO with no internal/audit fields", async () => {
  const { idToken } = await createAnonymousUser();
  const campaignId = nextId("camp");
  await seedCampaign(campaignId, { eligibleChannels: ["delivery"] });

  const { body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  const found = findCampaign(body.result!.campaigns, campaignId);
  assert.notStrictEqual(found, undefined);
  assert.strictEqual("organizationId" in found!, false);
  assert.strictEqual("active" in found!, false);
  assert.strictEqual("archived" in found!, false);
  assert.strictEqual("usageLimit" in found!, false);
  assert.strictEqual("perCustomerUsageLimit" in found!, false);
  assert.strictEqual("createdAt" in found!, false);
  assert.strictEqual("updatedAt" in found!, false);
  assert.deepStrictEqual(found!.eligibleChannels, ["delivery"]);
  assert.strictEqual(found!.campaignType, "percentageDiscount");
});

test("results are sorted by sortOrder", async () => {
  const { idToken } = await createAnonymousUser();
  const highId = nextId("camp");
  const lowId = nextId("camp");
  await seedCampaign(highId, { sortOrder: 50 });
  await seedCampaign(lowId, { sortOrder: 1 });

  const { body } = await callCallable(CAMPAIGNS_URL, {}, idToken);
  const campaigns = body.result!.campaigns;
  const lowIndex = campaigns.findIndex((c) => c.campaignId === lowId);
  const highIndex = campaigns.findIndex((c) => c.campaignId === highId);
  assert.ok(lowIndex >= 0 && highIndex >= 0);
  assert.ok(lowIndex < highIndex);
});
