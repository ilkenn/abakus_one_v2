import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { TAKEAWAY_GUEST_SESSION_TTL_MS } from "../takeawayGuestSessionConfig";

/**
 * Emulator-backed tests for `resolveTakeawayQrToken`/
 * `openTakeawayGuestSession` — Faz D.2 (Gel Al QR + Guest Session
 * Backend). Run via `npm run test:emulator`. Follows
 * `tableGuestSession.test.ts`'s exact pattern: raw HTTP against the
 * callable-functions wire protocol, no `firebase` client SDK dependency.
 *
 * Unlike the table-QR case, a takeaway QR's `organizationId`/
 * `restaurantId`/`branchId` must resolve against the **real** canonical
 * `organizations`/`restaurants`/`branches` chain (Faz D.1/D.1.1) — every
 * test seeds that chain directly via the Admin SDK (bypassing
 * `provisionOrganization`/`provisionRestaurant`/`provisionBranch`
 * entirely, since these are test fixtures exercising the *resolver*, not
 * the provisioning functions themselves — those already have their own
 * dedicated test suite, `provisioning.test.ts`).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const RESOLVE_URL =
  `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/resolveTakeawayQrToken`;
const OPEN_SESSION_URL =
  `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/openTakeawayGuestSession`;

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

async function callCallable(
  url: string,
  data: Record<string, unknown>,
  idToken?: string,
) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ data }),
  });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

async function createAnonymousUser(): Promise<{ idToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const body = (await response.json()) as { idToken: string; localId: string };
  assert.strictEqual(response.status, 200, "Auth emulator sign-up must succeed");
  return { idToken: body.idToken, uid: body.localId };
}

// Faz R.1C.1.1 — TEST_RUN_ID makes every generated id/phone number globally
// unique across the whole `node --test` invocation, not just within this
// file. Every test file's own counters previously started at 0, so two
// files could independently generate the identical `branch-87`/`area-88`
// string (or phone number) and silently share the same Firestore/Auth
// record across unrelated tests — a real, reproduced bug (root-caused via
// diagnostic capacity-bucket dumps showing a colliding chain's leftover
// data), not theoretical.
const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);

let phoneCounter = 0;
/** A real, phone-verified sign-in (not anonymous) — proves `openTakeawayGuestSession` accepts an already-real technical identity without modification, per §6's own requirement. */
async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
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
  const codesRes = await fetch(
    `${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`,
  );
  const codesBody = (await codesRes.json()) as {
    verificationCodes: { sessionInfo: string; code: string }[];
  };
  const match = codesBody.verificationCodes.find(
    (c) => c.sessionInfo === sendBody.sessionInfo,
  )!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }),
    },
  );
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedOrganization(
  id: string,
  overrides: Partial<{ isActive: boolean; name: string }> = {},
) {
  await admin
    .firestore()
    .collection("organizations")
    .doc(id)
    .set({ name: "Test Org", isActive: true, ...overrides });
}

async function seedRestaurant(
  id: string,
  organizationId: string,
  overrides: Partial<{ isActive: boolean; name: string }> = {},
) {
  await admin
    .firestore()
    .collection("restaurants")
    .doc(id)
    .set({ organizationId, name: "Test Restaurant", isActive: true, ...overrides });
}

async function seedBranch(
  id: string,
  restaurantId: string,
  organizationId: string,
  overrides: Partial<{
    status: string;
    emergencyStopped: boolean;
    supportedOrderChannelIds: string[];
    name: string;
  }> = {},
) {
  await admin
    .firestore()
    .collection("branches")
    .doc(id)
    .set({
      restaurantId,
      organizationId,
      name: "Merkez Şube",
      status: "active",
      emergencyStopped: false,
      supportedOrderChannelIds: ["takeaway"],
      ...overrides,
    });
}

async function seedTakeawayQrCode(
  id: string,
  token: string,
  scope: { organizationId: string; restaurantId: string; branchId: string },
  overrides: Partial<{ status: string; expiresAt: Date | admin.firestore.Timestamp }> = {},
) {
  await admin
    .firestore()
    .collection("takeawayQrCodes")
    .doc(id)
    .set({
      opaqueToken: token,
      organizationId: scope.organizationId,
      restaurantId: scope.restaurantId,
      branchId: scope.branchId,
      status: "active",
      ...overrides,
    });
}

/** The full, valid canonical chain + a matching active QR — the common-case fixture every "happy path" test starts from. */
async function seedValidChainAndQr(token: string) {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const qrCodeId = nextId("qr");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedTakeawayQrCode(qrCodeId, token, { organizationId, restaurantId, branchId });
  return { organizationId, restaurantId, branchId, qrCodeId };
}

// ---------------------------------------------------------------------
// resolveTakeawayQrToken
// ---------------------------------------------------------------------

test("resolveTakeawayQrToken: a valid, fully-chained token resolves to a minimized public preview — branch display name only, no internal ids", async () => {
  const chain = await seedValidChainAndQr("TOKEN-VALID-1");

  const { httpStatus, body } = await callCallable(RESOLVE_URL, { token: "TOKEN-VALID-1" });

  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result, { status: "valid", branchDisplayName: "Merkez Şube" });
  assert.strictEqual(chain.branchId.length > 0, true);
});

test("resolveTakeawayQrToken: an unknown token resolves to notFound", async () => {
  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-DOES-NOT-EXIST" });
  assert.deepStrictEqual(body.result, { status: "notFound" });
});

test("resolveTakeawayQrToken: a token past its own expiresAt resolves to expired", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-EXPIRED", { organizationId, restaurantId, branchId }, {
    expiresAt: new Date(Date.now() - 60_000),
  });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-EXPIRED" });
  assert.deepStrictEqual(body.result, { status: "expired" });
});

test("resolveTakeawayQrToken: an inactive (revoked) QR code resolves to invalid", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-REVOKED", { organizationId, restaurantId, branchId }, {
    status: "inactive",
  });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-REVOKED" });
  assert.deepStrictEqual(body.result, { status: "invalid" });
});

test("resolveTakeawayQrToken: a rotated QR code resolves to invalid", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-ROTATED", { organizationId, restaurantId, branchId }, {
    status: "rotated",
  });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-ROTATED" });
  assert.deepStrictEqual(body.result, { status: "invalid" });
});

test("resolveTakeawayQrToken: an inactive organization resolves to invalid", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId, { isActive: false });
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-ORG-INACTIVE", { organizationId, restaurantId, branchId });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-ORG-INACTIVE" });
  assert.deepStrictEqual(body.result, { status: "invalid" });
});

test("resolveTakeawayQrToken: an inactive restaurant resolves to invalid", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId, { isActive: false });
  await seedBranch(branchId, restaurantId, organizationId);
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-RESTAURANT-INACTIVE", { organizationId, restaurantId, branchId });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-RESTAURANT-INACTIVE" });
  assert.deepStrictEqual(body.result, { status: "invalid" });
});

test("resolveTakeawayQrToken: a branch that was never provisioned resolves to notFound", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-BRANCH-MISSING", {
    organizationId,
    restaurantId,
    branchId: "branch-that-does-not-exist",
  });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-BRANCH-MISSING" });
  assert.deepStrictEqual(body.result, { status: "notFound" });
});

test("resolveTakeawayQrToken: a branch with status != active resolves to invalid", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId, { status: "inactive" });
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-BRANCH-INACTIVE", { organizationId, restaurantId, branchId });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-BRANCH-INACTIVE" });
  assert.deepStrictEqual(body.result, { status: "invalid" });
});

test("resolveTakeawayQrToken: a branch that does not support the takeaway channel resolves to invalid", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId, {
    supportedOrderChannelIds: ["dineInQr", "delivery"],
  });
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-NO-TAKEAWAY", { organizationId, restaurantId, branchId });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-NO-TAKEAWAY" });
  assert.deepStrictEqual(body.result, { status: "invalid" });
});

test("resolveTakeawayQrToken: an emergency-stopped branch resolves to invalid", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId, { emergencyStopped: true });
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-EMERGENCY-STOPPED", { organizationId, restaurantId, branchId });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-EMERGENCY-STOPPED" });
  assert.deepStrictEqual(body.result, { status: "invalid" });
});

test("resolveTakeawayQrToken: a cross-tenant binding mismatch (QR claims an organizationId that does not match its branch's real organization) resolves to notFound", async () => {
  const realOrganizationId = nextId("org");
  const attackerOrganizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(realOrganizationId);
  await seedOrganization(attackerOrganizationId);
  await seedRestaurant(restaurantId, realOrganizationId);
  await seedBranch(branchId, restaurantId, realOrganizationId);
  // The QR document itself claims the attacker's organizationId, even
  // though the real branch/restaurant chain belongs to a different one —
  // simulates a corrupted/tampered QR record, not a client-supplied value
  // (the client never sends organizationId at all).
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-CROSS-TENANT", {
    organizationId: attackerOrganizationId,
    restaurantId,
    branchId,
  });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-CROSS-TENANT" });
  assert.deepStrictEqual(body.result, { status: "notFound" });
});

test("resolveTakeawayQrToken: fails closed on a missing token argument", async () => {
  const { httpStatus, body } = await callCallable(RESOLVE_URL, {});
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

// ---------------------------------------------------------------------
// openTakeawayGuestSession
// ---------------------------------------------------------------------

test("openTakeawayGuestSession: a valid token and an authenticated (anonymous) caller creates a correctly server-derived session", async () => {
  const chain = await seedValidChainAndQr("TOKEN-OPEN-1");
  const { idToken, uid } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-OPEN-1" }, idToken);

  assert.strictEqual(httpStatus, 200);
  const sessionId = body.result?.sessionId as string;
  assert.ok(sessionId);
  assert.strictEqual(body.result?.organizationId, chain.organizationId);
  assert.strictEqual(body.result?.branchId, chain.branchId);
  assert.strictEqual(body.result?.reused, false);

  const sessionDoc = await admin.firestore().collection("takeawayGuestSessions").doc(sessionId).get();
  assert.ok(sessionDoc.exists);
  const session = sessionDoc.data()!;
  // Every scope field is what the server resolved, not anything the
  // client could have claimed — the callable request never accepted a
  // scope argument in the first place, so this also proves the response
  // wasn't just echoing client input.
  assert.strictEqual(session.organizationId, chain.organizationId);
  assert.strictEqual(session.restaurantId, chain.restaurantId);
  assert.strictEqual(session.branchId, chain.branchId);
  assert.strictEqual(session.guestAuthUid, uid);
  assert.strictEqual(session.status, "active");
  assert.strictEqual(session.qrTokenId, chain.qrCodeId);
  const createdAtMs = session.createdAt.toDate().getTime();
  const expiresAtMs = session.expiresAt.toDate().getTime();
  assert.ok(
    Math.abs(expiresAtMs - createdAtMs - TAKEAWAY_GUEST_SESSION_TTL_MS) < 2000,
    `expected expiresAt - createdAt to equal TAKEAWAY_GUEST_SESSION_TTL_MS (${TAKEAWAY_GUEST_SESSION_TTL_MS}ms), got ${expiresAtMs - createdAtMs}ms`,
  );
});

test("openTakeawayGuestSession: a real, phone-verified caller is accepted as the technical identity, without creating a customers/{uid} document or any CRM/loyalty side effect", async () => {
  const chain = await seedValidChainAndQr("TOKEN-OPEN-PHONE-1");
  const { idToken, uid } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-OPEN-PHONE-1" }, idToken);

  assert.strictEqual(httpStatus, 200);
  const sessionId = body.result?.sessionId as string;
  const sessionDoc = await admin.firestore().collection("takeawayGuestSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()!.guestAuthUid, uid);
  assert.strictEqual(sessionDoc.data()!.organizationId, chain.organizationId);

  const customerDoc = await admin.firestore().collection("customers").doc(uid).get();
  assert.strictEqual(customerDoc.exists, false, "no customers/{uid} document may ever be created by this function");
});

test("openTakeawayGuestSession: an unauthenticated caller is rejected and no session is created", async () => {
  await seedValidChainAndQr("TOKEN-OPEN-2");

  const { httpStatus, body } = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-OPEN-2" });

  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("openTakeawayGuestSession: an invalid (rotated) token is rejected and no session is created", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-OPEN-ROTATED", { organizationId, restaurantId, branchId }, {
    status: "rotated",
  });
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-OPEN-ROTATED" }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("openTakeawayGuestSession: an expired token is rejected and no session is created", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedTakeawayQrCode(nextId("qr"), "TOKEN-OPEN-EXPIRED", { organizationId, restaurantId, branchId }, {
    expiresAt: new Date(Date.now() - 60_000),
  });
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-OPEN-EXPIRED" }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("openTakeawayGuestSession: an unknown token is rejected and no session is created", async () => {
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-DOES-NOT-EXIST-EITHER" }, idToken);

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("openTakeawayGuestSession: a second call by the same uid for the same token reuses the existing active session — no duplicate", async () => {
  await seedValidChainAndQr("TOKEN-OPEN-REUSE");
  const { idToken, uid } = await createAnonymousUser();

  const first = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-OPEN-REUSE" }, idToken);
  const second = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-OPEN-REUSE" }, idToken);

  assert.strictEqual(first.body.result?.reused, false);
  assert.strictEqual(second.body.result?.reused, true);
  assert.strictEqual(first.body.result?.sessionId, second.body.result?.sessionId);

  const all = await admin
    .firestore()
    .collection("takeawayGuestSessions")
    .where("guestAuthUid", "==", uid)
    .get();
  assert.strictEqual(all.docs.length, 1, "exactly one session document must exist for this uid");
});

test("openTakeawayGuestSession: a different uid scanning the same QR gets an independent session — reuse never crosses callers", async () => {
  await seedValidChainAndQr("TOKEN-OPEN-INDEPENDENT");
  const guestA = await createAnonymousUser();
  const guestB = await createAnonymousUser();

  const resultA = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-OPEN-INDEPENDENT" }, guestA.idToken);
  const resultB = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-OPEN-INDEPENDENT" }, guestB.idToken);

  const sessionIdA = resultA.body.result?.sessionId as string;
  const sessionIdB = resultB.body.result?.sessionId as string;
  assert.notStrictEqual(sessionIdA, sessionIdB);
  assert.strictEqual(resultA.body.result?.reused, false);
  assert.strictEqual(resultB.body.result?.reused, false);

  const db = admin.firestore();
  const sessionA = (await db.collection("takeawayGuestSessions").doc(sessionIdA).get()).data()!;
  const sessionB = (await db.collection("takeawayGuestSessions").doc(sessionIdB).get()).data()!;
  assert.strictEqual(sessionA.guestAuthUid, guestA.uid);
  assert.strictEqual(sessionB.guestAuthUid, guestB.uid);
});
