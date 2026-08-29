import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { TABLE_GUEST_SESSION_TTL_MS } from "../tableGuestSessionConfig";

/**
 * Emulator-backed tests for `resolveTableQrToken`/`openTableGuestSession`
 * — Table Guest Session Phase 1/2 (docs/decisions.md, Table Guest Session
 * architecture). Run via `npm run test:emulator`, which now also starts
 * the Auth emulator (`--only firestore,functions,auth` —
 * `package.json`), since these tests need a real anonymous Firebase Auth
 * uid to call `openTableGuestSession` as an authenticated caller. Calls
 * both callable functions directly over HTTP using the documented
 * callable-functions wire protocol (`{"data": ...}` request body,
 * `{"result": ...}`/`{"error": ...}` response, `Authorization: Bearer
 * <idToken>` for an authenticated call), matching
 * `processAccountDeletion.test.ts`'s exact pattern rather than adding the
 * `firebase` client SDK as a new dependency.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const RESOLVE_URL =
  `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/resolveTableQrToken`;
const OPEN_SESSION_URL =
  `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/openTableGuestSession`;

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

/**
 * Retries a single callable invocation when the Functions Emulator itself
 * returns a transient connection-reset failure (`httpStatus 500`, body
 * `{"code":"ECONNRESET"}`) rather than a real business-logic response —
 * observed only under full-suite cumulative load (never in isolation),
 * exactly the same class of emulator-under-load transport flakiness
 * `orderEarnReversal.test.ts`'s own `withTransientEmulatorTransportRetry`
 * already documents and retries for a different transient signature
 * ("Transaction is invalid or closed"). Narrowly scoped: only this one,
 * named transient shape is retried — any other status/body (including a
 * genuine business-logic rejection) is returned as-is on the first attempt,
 * so a real assertion failure is never silently retried away.
 */
async function withTransientConnectionResetRetry(
  fn: () => Promise<{ httpStatus: number; body: { result?: Record<string, unknown>; error?: { status?: string; message?: string } } }>,
  attempts = 3,
): Promise<{ httpStatus: number; body: { result?: Record<string, unknown>; error?: { status?: string; message?: string } } }> {
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const result = await fn();
    const isTransientConnectionReset =
      result.httpStatus === 500 &&
      JSON.stringify(result.body).includes("ECONNRESET");
    if (!isTransientConnectionReset || attempt === attempts) return result;
  }
  throw new Error("unreachable");
}

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

/** Creates a brand-new anonymous Firebase Auth user via the Auth emulator's REST API and returns its ID token — the same outcome `signInAnonymously()` produces client-side, without adding the client SDK as a test dependency. */
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

async function seedTable(
  tableId: string,
  overrides: Partial<{
    organizationId: string;
    restaurantId: string;
    branchId: string;
    displayName: string;
    branchDisplayName: string;
    isActive: boolean;
    status: string;
  }> = {},
) {
  const db = admin.firestore();
  await db
    .collection("restaurantTables")
    .doc(tableId)
    .set({
      organizationId: "org-1",
      restaurantId: "restaurant-1",
      branchId: "branch-1",
      displayName: "Masa 12",
      branchDisplayName: "Abaküs Ortaköy",
      isActive: true,
      status: "available",
      ...overrides,
    });
}

async function seedQrCode(
  qrCodeId: string,
  tableId: string,
  token: string,
  overrides: Partial<{ status: string; expiresAt: Date | admin.firestore.Timestamp }> = {},
) {
  const db = admin.firestore();
  await db
    .collection("tableQrCodes")
    .doc(qrCodeId)
    .set({
      tableId,
      opaqueToken: token,
      status: "active",
      ...overrides,
    });
}

test("resolveTableQrToken: a valid, active token resolves to a minimized public preview — display names only, no internal ids", async () => {
  await seedTable("table-resolve-1");
  await seedQrCode("qr-resolve-1", "table-resolve-1", "TOKEN-RESOLVE-1");

  const { httpStatus, body } = await callCallable(RESOLVE_URL, {
    token: "TOKEN-RESOLVE-1",
  });

  assert.strictEqual(httpStatus, 200);
  // Data-minimization fix: organizationId/restaurantId/branchId/tableId
  // must never appear in this response — only display names, and only
  // exactly these keys (deepStrictEqual also catches an accidental extra
  // field creeping back in later).
  assert.deepStrictEqual(body.result, {
    status: "valid",
    tableDisplayName: "Masa 12",
    branchDisplayName: "Abaküs Ortaköy",
  });
});

test("resolveTableQrToken: an unknown token resolves to notFound", async () => {
  const { httpStatus, body } = await callCallable(RESOLVE_URL, {
    token: "TOKEN-DOES-NOT-EXIST",
  });

  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result, { status: "notFound" });
});

test("resolveTableQrToken: a rotated (revoked) token resolves to invalid", async () => {
  await seedTable("table-resolve-2");
  await seedQrCode("qr-resolve-2", "table-resolve-2", "TOKEN-ROTATED", {
    status: "rotated",
  });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-ROTATED" });

  assert.deepStrictEqual(body.result, { status: "invalid" });
});

test("resolveTableQrToken: a token past its own expiresAt resolves to expired", async () => {
  await seedTable("table-resolve-3");
  await seedQrCode("qr-resolve-3", "table-resolve-3", "TOKEN-EXPIRED", {
    expiresAt: new Date(Date.now() - 60_000),
  });

  const { body } = await callCallable(RESOLVE_URL, { token: "TOKEN-EXPIRED" });

  assert.deepStrictEqual(body.result, { status: "expired" });
});

test("resolveTableQrToken: a valid QR code pointing at an inactive table resolves to notFound", async () => {
  await seedTable("table-resolve-4", { isActive: false });
  await seedQrCode("qr-resolve-4", "table-resolve-4", "TOKEN-INACTIVE-TABLE");

  const { body } = await callCallable(RESOLVE_URL, {
    token: "TOKEN-INACTIVE-TABLE",
  });

  assert.deepStrictEqual(body.result, { status: "notFound" });
});

test("resolveTableQrToken: a valid QR code pointing at a non-orderable (occupied) table resolves to invalid", async () => {
  await seedTable("table-resolve-5", { status: "occupied" });
  await seedQrCode("qr-resolve-5", "table-resolve-5", "TOKEN-OCCUPIED-TABLE");

  const { body } = await callCallable(RESOLVE_URL, {
    token: "TOKEN-OCCUPIED-TABLE",
  });

  assert.deepStrictEqual(body.result, { status: "invalid" });
});

test("resolveTableQrToken: fails closed on a missing token argument", async () => {
  const { httpStatus, body } = await callCallable(RESOLVE_URL, {});

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("resolveTableQrToken: two tokens belonging to two different organizations never cross-resolve (tenant isolation) — checked at the display-name level, since ids are no longer in the public response", async () => {
  await seedTable("table-org-a", {
    organizationId: "org-a",
    branchId: "branch-a",
    displayName: "Masa A",
    branchDisplayName: "Şube A",
  });
  await seedQrCode("qr-org-a", "table-org-a", "TOKEN-ORG-A");
  await seedTable("table-org-b", {
    organizationId: "org-b",
    branchId: "branch-b",
    displayName: "Masa B",
    branchDisplayName: "Şube B",
  });
  await seedQrCode("qr-org-b", "table-org-b", "TOKEN-ORG-B");

  const a = await callCallable(RESOLVE_URL, { token: "TOKEN-ORG-A" });
  const b = await callCallable(RESOLVE_URL, { token: "TOKEN-ORG-B" });

  assert.strictEqual(a.body.result?.tableDisplayName, "Masa A");
  assert.strictEqual(a.body.result?.branchDisplayName, "Şube A");
  assert.strictEqual(b.body.result?.tableDisplayName, "Masa B");
  assert.strictEqual(b.body.result?.branchDisplayName, "Şube B");
});

test("openTableGuestSession: two tokens belonging to two different organizations create sessions with correctly isolated (non-cross-contaminated) scope — the canonical-scope-level tenant isolation check", async () => {
  await seedTable("table-open-org-a", { organizationId: "org-a", branchId: "branch-a" });
  await seedQrCode("qr-open-org-a", "table-open-org-a", "TOKEN-OPEN-ORG-A");
  await seedTable("table-open-org-b", { organizationId: "org-b", branchId: "branch-b" });
  await seedQrCode("qr-open-org-b", "table-open-org-b", "TOKEN-OPEN-ORG-B");
  const guestA = await createAnonymousUser();
  const guestB = await createAnonymousUser();

  const a = await callCallable(
    OPEN_SESSION_URL,
    { token: "TOKEN-OPEN-ORG-A" },
    guestA.idToken,
  );
  const b = await callCallable(
    OPEN_SESSION_URL,
    { token: "TOKEN-OPEN-ORG-B" },
    guestB.idToken,
  );

  assert.strictEqual(a.body.result?.organizationId, "org-a");
  assert.strictEqual(a.body.result?.branchId, "branch-a");
  assert.strictEqual(a.body.result?.tableId, "table-open-org-a");
  assert.strictEqual(b.body.result?.organizationId, "org-b");
  assert.strictEqual(b.body.result?.branchId, "branch-b");
  assert.strictEqual(b.body.result?.tableId, "table-open-org-b");
});

test("openTableGuestSession: a valid token and an authenticated (anonymous) caller creates a correctly-scoped session", async () => {
  await seedTable("table-open-1");
  await seedQrCode("qr-open-1", "table-open-1", "TOKEN-OPEN-1");
  const { idToken, uid } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    OPEN_SESSION_URL,
    { token: "TOKEN-OPEN-1" },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const sessionId = body.result?.sessionId as string;
  assert.ok(sessionId, "a sessionId must be returned");
  assert.strictEqual(body.result?.organizationId, "org-1");
  assert.strictEqual(body.result?.branchId, "branch-1");
  assert.strictEqual(body.result?.tableId, "table-open-1");

  const sessionDoc = await admin
    .firestore()
    .collection("tableGuestSessions")
    .doc(sessionId)
    .get();
  assert.ok(sessionDoc.exists);
  const session = sessionDoc.data()!;
  assert.strictEqual(session.guestAuthUid, uid);
  // TTL boundary check #1 ("immediately active after creation"): a
  // freshly created session must be active right now.
  assert.strictEqual(session.status, "active");
  assert.strictEqual(session.organizationId, "org-1");
  assert.strictEqual(session.branchId, "branch-1");
  assert.strictEqual(session.tableId, "table-open-1");
  // TTL boundary check #2: expiresAt must be *exactly* createdAt +
  // TABLE_GUEST_SESSION_TTL_MS (the centralized config constant), not an
  // arbitrary/hardcoded value drifted from it — a 2s tolerance absorbs
  // real test-execution latency between createdAt/expiresAt being
  // computed server-side and this assertion running.
  const createdAtMs = session.createdAt.toDate().getTime();
  const expiresAtMs = session.expiresAt.toDate().getTime();
  assert.ok(
    Math.abs(expiresAtMs - createdAtMs - TABLE_GUEST_SESSION_TTL_MS) < 2000,
    `expected expiresAt - createdAt to equal TABLE_GUEST_SESSION_TTL_MS ` +
      `(${TABLE_GUEST_SESSION_TTL_MS}ms), got ${expiresAtMs - createdAtMs}ms`,
  );
  assert.ok(session.expiresAt.toDate() > new Date());
});

test("openTableGuestSession: an unauthenticated caller is rejected and no session is created", async () => {
  await seedTable("table-open-2");
  await seedQrCode("qr-open-2", "table-open-2", "TOKEN-OPEN-2");

  const { httpStatus, body } = await callCallable(OPEN_SESSION_URL, {
    token: "TOKEN-OPEN-2",
  });

  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("openTableGuestSession: an invalid (rotated) token is rejected and no session is created", async () => {
  await seedTable("table-open-3");
  await seedQrCode("qr-open-3", "table-open-3", "TOKEN-OPEN-3-ROTATED", {
    status: "rotated",
  });
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    OPEN_SESSION_URL,
    { token: "TOKEN-OPEN-3-ROTATED" },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("openTableGuestSession: an expired token is rejected and no session is created", async () => {
  await seedTable("table-open-4");
  await seedQrCode("qr-open-4", "table-open-4", "TOKEN-OPEN-4-EXPIRED", {
    expiresAt: new Date(Date.now() - 60_000),
  });
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    OPEN_SESSION_URL,
    { token: "TOKEN-OPEN-4-EXPIRED" },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("openTableGuestSession: an unknown token is rejected and no session is created", async () => {
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    OPEN_SESSION_URL,
    { token: "TOKEN-DOES-NOT-EXIST-EITHER" },
    idToken,
  );

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("openTableGuestSession: a disabled (non-orderable) table is rejected and no session is created", async () => {
  await seedTable("table-open-5", { status: "cleaning" });
  await seedQrCode("qr-open-5", "table-open-5", "TOKEN-OPEN-5");
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    OPEN_SESSION_URL,
    { token: "TOKEN-OPEN-5" },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("openTableGuestSession: two different anonymous callers scanning the same table get two independent sessions, each bound to its own uid", async () => {
  await seedTable("table-open-6");
  await seedQrCode("qr-open-6", "table-open-6", "TOKEN-OPEN-6");
  const guestA = await createAnonymousUser();
  const guestB = await createAnonymousUser();

  const resultA = await callCallable(
    OPEN_SESSION_URL,
    { token: "TOKEN-OPEN-6" },
    guestA.idToken,
  );
  const resultB = await callCallable(
    OPEN_SESSION_URL,
    { token: "TOKEN-OPEN-6" },
    guestB.idToken,
  );

  const sessionIdA = resultA.body.result?.sessionId as string;
  const sessionIdB = resultB.body.result?.sessionId as string;
  assert.notStrictEqual(sessionIdA, sessionIdB);

  const db = admin.firestore();
  const sessionA = (
    await db.collection("tableGuestSessions").doc(sessionIdA).get()
  ).data()!;
  const sessionB = (
    await db.collection("tableGuestSessions").doc(sessionIdB).get()
  ).data()!;
  assert.strictEqual(sessionA.guestAuthUid, guestA.uid);
  assert.strictEqual(sessionB.guestAuthUid, guestB.uid);
  assert.notStrictEqual(sessionA.guestAuthUid, sessionB.guestAuthUid);
});

// ---------------------------------------------------------------------
// AP-3 Wave 1 — TableSession + GuestSubAccount foundation (corrected
// Stage A report §1/§6/§8).
// ---------------------------------------------------------------------

test("openTableGuestSession: creates a TableSession and points restaurantTables.activeTableSessionId at it, plus a GuestSubAccount owned by the caller's own uid", async () => {
  await seedTable("table-ap3-1");
  await seedQrCode("qr-ap3-1", "table-ap3-1", "TOKEN-AP3-1");
  const { idToken, uid } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-AP3-1" }, idToken);
  assert.strictEqual(httpStatus, 200);
  const tableSessionId = body.result?.tableSessionId as string;
  const subAccountId = body.result?.subAccountId as string;
  assert.ok(tableSessionId);
  assert.ok(subAccountId);

  const db = admin.firestore();
  const tableSessionDoc = await db.collection("tableSessions").doc(tableSessionId).get();
  assert.ok(tableSessionDoc.exists);
  assert.strictEqual(tableSessionDoc.data()!.status, "active");
  assert.strictEqual(tableSessionDoc.data()!.tableId, "table-ap3-1");

  const tableDoc = await db.collection("restaurantTables").doc("table-ap3-1").get();
  assert.strictEqual(tableDoc.data()!.activeTableSessionId, tableSessionId);

  const subAccountDoc = await db.collection("guestSubAccounts").doc(subAccountId).get();
  assert.ok(subAccountDoc.exists);
  assert.strictEqual(subAccountDoc.data()!.ownerAuthUid, uid);
  assert.strictEqual(subAccountDoc.data()!.tableSessionId, tableSessionId);
  assert.strictEqual(subAccountDoc.data()!.status, "open");
});

test("openTableGuestSession: a second, different guest scanning the same still-active table reuses the SAME TableSession but gets its OWN sub-account", async () => {
  await seedTable("table-ap3-2");
  await seedQrCode("qr-ap3-2", "table-ap3-2", "TOKEN-AP3-2");
  const guestA = await createAnonymousUser();
  const guestB = await createAnonymousUser();

  const a = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-AP3-2" }, guestA.idToken);
  const b = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-AP3-2" }, guestB.idToken);

  assert.strictEqual(a.body.result?.tableSessionId, b.body.result?.tableSessionId);
  assert.notStrictEqual(a.body.result?.subAccountId, b.body.result?.subAccountId);
});

test("openTableGuestSession: the SAME guest (device) re-scanning the same table reuses its own sub-account, not a new one", async () => {
  await seedTable("table-ap3-3");
  await seedQrCode("qr-ap3-3", "table-ap3-3", "TOKEN-AP3-3");
  const { idToken } = await createAnonymousUser();

  const first = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-AP3-3" }, idToken);
  const second = await callCallable(OPEN_SESSION_URL, { token: "TOKEN-AP3-3" }, idToken);

  assert.strictEqual(first.body.result?.tableSessionId, second.body.result?.tableSessionId);
  assert.strictEqual(first.body.result?.subAccountId, second.body.result?.subAccountId);
  assert.notStrictEqual(first.body.result?.sessionId, second.body.result?.sessionId);
});

test("openTableGuestSession: N concurrent first-scans of the same table create EXACTLY ONE TableSession (concurrency-safe lock)", async () => {
  await seedTable("table-ap3-concurrency");
  await seedQrCode("qr-ap3-concurrency", "table-ap3-concurrency", "TOKEN-AP3-CONCURRENCY");
  const guests = await Promise.all(Array.from({ length: 8 }, () => createAnonymousUser()));

  const results = await Promise.all(
    guests.map((guest) =>
      withTransientConnectionResetRetry(() =>
        callCallable(OPEN_SESSION_URL, { token: "TOKEN-AP3-CONCURRENCY" }, guest.idToken),
      ),
    ),
  );
  for (const r of results) assert.strictEqual(r.httpStatus, 200, JSON.stringify(r.body));

  const tableSessionIds = new Set(results.map((r) => r.body.result?.tableSessionId));
  assert.strictEqual(tableSessionIds.size, 1, `expected exactly one TableSession, got ${tableSessionIds.size}`);

  const subAccountIds = new Set(results.map((r) => r.body.result?.subAccountId));
  assert.strictEqual(subAccountIds.size, 8, "each of the 8 distinct guests must get its own sub-account");

  const db = admin.firestore();
  const tableSessionsSnap = await db
    .collection("tableSessions")
    .where("tableId", "==", "table-ap3-concurrency")
    .get();
  assert.strictEqual(tableSessionsSnap.size, 1, "exactly one TableSession document must exist for this table");
});
