import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  defaultClaimsRevocationLookup,
  requireStaffPermission,
} from "../staffAuthorization";
import type { CallableRequest } from "firebase-functions/v2/https";

/**
 * Emulator-backed proof that `defaultClaimsRevocationLookup` — the real
 * Firestore-backed path `requireStaffPermission`/`requireBranchAccess` use
 * whenever a caller doesn't inject a fake one — actually reads
 * `authClaimsRevocations/{uid}` correctly, and that `requireStaffPermission`
 * itself rejects/accepts correctly when going through that real path (not
 * just the fake-lookup-injected pure unit tests in
 * `staffAuthorization.test.ts`, which never touch Firestore at all).
 *
 * Calls `defaultClaimsRevocationLookup`/`requireStaffPermission` directly,
 * in-process, against the real Firestore emulator — not through any
 * deployed callable's HTTP endpoint — mirroring
 * `callableRateLimitEnforcement.test.ts`'s exact reasoning: this needs
 * nothing from the separate Functions Emulator process, so it stays
 * completely isolated from every other emulator test file.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

function fakeRequest(iatSeconds: number, uid: string): CallableRequest {
  return {
    auth: {
      uid,
      token: {
        iat: iatSeconds,
        organizationAccess: ["org-1"],
        roles: { "org-1": ["admin"] },
      },
    },
    data: {},
  } as unknown as CallableRequest;
}

test("defaultClaimsRevocationLookup: a uid with no authClaimsRevocations doc resolves null", async () => {
  const result = await defaultClaimsRevocationLookup("uid-never-revoked");
  assert.strictEqual(result, null);
});

test("defaultClaimsRevocationLookup: a uid with a stamped revokedAt resolves its millisecond value", async () => {
  const uid = "uid-with-revocation";
  const revokedAt = new Date("2026-10-20T12:00:00.000Z");
  await admin.firestore().collection("authClaimsRevocations").doc(uid).set({
    revokedAt: admin.firestore.Timestamp.fromDate(revokedAt),
  });

  const result = await defaultClaimsRevocationLookup(uid);
  assert.strictEqual(result, revokedAt.getTime());
});

test("requireStaffPermission (real Firestore path, no injected lookup): a token issued before the real stamped revocation is rejected", async () => {
  const uid = "uid-real-path-stale";
  const revokedAt = new Date();
  await admin.firestore().collection("authClaimsRevocations").doc(uid).set({
    revokedAt: admin.firestore.Timestamp.fromDate(revokedAt),
  });
  const staleToken = fakeRequest(Math.floor((revokedAt.getTime() - 60_000) / 1000), uid);

  await assert.rejects(
    requireStaffPermission(staleToken, "org-1", "manageStaffAccounts"),
    (err: unknown) => (err as { code?: string }).code === "permission-denied",
  );
});

test("requireStaffPermission (real Firestore path, no injected lookup): a token issued after the real stamped revocation succeeds", async () => {
  const uid = "uid-real-path-fresh";
  const revokedAt = new Date();
  await admin.firestore().collection("authClaimsRevocations").doc(uid).set({
    revokedAt: admin.firestore.Timestamp.fromDate(revokedAt),
  });
  const freshToken = fakeRequest(Math.floor((revokedAt.getTime() + 60_000) / 1000), uid);

  await assert.doesNotReject(
    requireStaffPermission(freshToken, "org-1", "manageStaffAccounts"),
  );
});
