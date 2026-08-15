import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { getFirestore } from "firebase-admin/firestore";

/**
 * Emulator-backed tests for Faz R.3C.1 — the `registerDeviceToken` server-
 * authoritative callable that replaced R.3C's direct-client-write device-
 * token registration path. Mirrors every prior reservation-phase test
 * file's exact pattern (raw HTTP against the callable-functions wire
 * protocol, anonymous-sign-up-minted identities).
 *
 * **Why this needed a real callable, verified here against the real
 * emulator, not just InMemory unit tests**: `firestore.rules`'s
 * `deviceTokens` read rule only ever lets a caller see their own
 * documents, so a client-side "does this token already belong to someone
 * else" check cannot work — only an Admin-SDK-backed callable can see
 * across owners. These tests exercise the real callable against the real
 * Firestore emulator, proving the reassociation actually happens
 * server-side, not merely that the InMemory fixture's own logic is
 * correct in isolation.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const REGISTER_URL = fn("registerDeviceToken");

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

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let seq = 0;
const nextToken = () => `fcm-token-${TEST_RUN_ID}-${++seq}`;

async function activeTokensForUid(uid: string) {
  const snapshot = await getFirestore()
    .collection("deviceTokens")
    .where("uid", "==", uid)
    .where("revokedAt", "==", null)
    .get();
  return snapshot.docs.map((d) => d.data());
}

test("registerDeviceToken: an unauthenticated caller is rejected", async () => {
  const { httpStatus, body } = await callCallable(REGISTER_URL, {
    token: nextToken(),
    platform: "android",
  });

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("registerDeviceToken: a signed-in caller registers a brand-new token for themselves", async () => {
  const { idToken, uid } = await signUpAnonymously();
  const token = nextToken();

  const { httpStatus, body } = await callCallable(
    REGISTER_URL,
    { token, platform: "android" },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.reused, false);

  const active = await activeTokensForUid(uid);
  assert.strictEqual(active.length, 1);
  assert.strictEqual(active[0].token, token);
  assert.strictEqual(active[0].organizationId, "org-1");
});

test("registerDeviceToken: re-registering the same token for the same uid is idempotent (reused, not duplicated)", async () => {
  const { idToken, uid } = await signUpAnonymously();
  const token = nextToken();

  const first = await callCallable(REGISTER_URL, { token, platform: "android" }, idToken);
  const second = await callCallable(REGISTER_URL, { token, platform: "android" }, idToken);

  assert.strictEqual(first.body.result?.reused, false);
  assert.strictEqual(second.body.result?.reused, true);
  assert.strictEqual(first.body.result?.tokenId, second.body.result?.tokenId);

  const active = await activeTokensForUid(uid);
  assert.strictEqual(active.length, 1, "must never create a duplicate document for the same uid+token");
});

test("registerDeviceToken: one customer can register multiple distinct devices", async () => {
  const { idToken, uid } = await signUpAnonymously();

  await callCallable(REGISTER_URL, { token: nextToken(), platform: "android" }, idToken);
  await callCallable(REGISTER_URL, { token: nextToken(), platform: "ios" }, idToken);

  const active = await activeTokensForUid(uid);
  assert.strictEqual(active.length, 2);
});

test("registerDeviceToken: the SAME physical token re-registering under a DIFFERENT uid revokes the old owner and activates only the new one", async () => {
  const customerA = await signUpAnonymously();
  const customerB = await signUpAnonymously();
  const sharedToken = nextToken();

  await callCallable(REGISTER_URL, { token: sharedToken, platform: "android" }, customerA.idToken);
  const second = await callCallable(
    REGISTER_URL,
    { token: sharedToken, platform: "android" },
    customerB.idToken,
  );

  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.reused, false);

  const activeForA = await activeTokensForUid(customerA.uid);
  assert.strictEqual(activeForA.length, 0, "customer A must no longer hold an active token after B re-registers the same physical device");

  const activeForB = await activeTokensForUid(customerB.uid);
  assert.strictEqual(activeForB.length, 1);
  assert.strictEqual(activeForB[0].token, sharedToken);

  // The physical token value must never be simultaneously active under
  // two different customer uids — the exact invariant this callable
  // exists to enforce.
  const allActiveWithThisToken = await getFirestore()
    .collection("deviceTokens")
    .where("token", "==", sharedToken)
    .where("revokedAt", "==", null)
    .get();
  assert.strictEqual(allActiveWithThisToken.docs.length, 1);
});

test("registerDeviceToken: customer B registering a token never touches customer A's OTHER, unrelated tokens", async () => {
  const customerA = await signUpAnonymously();
  const customerB = await signUpAnonymously();
  const aOwnToken = nextToken();
  const sharedToken = nextToken();

  await callCallable(REGISTER_URL, { token: aOwnToken, platform: "android" }, customerA.idToken);
  await callCallable(REGISTER_URL, { token: sharedToken, platform: "android" }, customerA.idToken);
  await callCallable(REGISTER_URL, { token: sharedToken, platform: "android" }, customerB.idToken);

  const activeForA = await activeTokensForUid(customerA.uid);
  assert.strictEqual(activeForA.length, 1, "customer A's own unrelated device must remain active");
  assert.strictEqual(activeForA[0].token, aOwnToken);
});

test("registerDeviceToken: a spoofed uid in the request body is ignored — uid always comes from the authenticated caller", async () => {
  const { idToken, uid } = await signUpAnonymously();
  const token = nextToken();

  await callCallable(REGISTER_URL, { token, platform: "android", uid: "someone-else" }, idToken);

  const active = await activeTokensForUid(uid);
  assert.strictEqual(active.length, 1, "the token must be registered under the real authenticated uid, never a client-supplied one");
});

test("registerDeviceToken: a missing token argument is rejected", async () => {
  const { idToken } = await signUpAnonymously();
  const { httpStatus, body } = await callCallable(REGISTER_URL, { platform: "android" }, idToken);

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("registerDeviceToken: a missing platform argument is rejected", async () => {
  const { idToken } = await signUpAnonymously();
  const { httpStatus, body } = await callCallable(REGISTER_URL, { token: nextToken() }, idToken);

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});
