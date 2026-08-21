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
    minorUnitsUntilNextBoncuk: 1000,
    lifetimeEarned: 0,
    lifetimeRedeemed: 0,
    policy: {
      earningSpendMinorUnits: 5000,
      earningBoncukAmount: 5,
      redemptionValueMinorUnitsPerBoncuk: 100,
      maxRedemptionBasisPoints: 5000,
    },
  });

  const data = await accountDoc(uid);
  assert.strictEqual(data?.organizationId, SINGLE_TENANT_ORGANIZATION_ID);
  assert.strictEqual(data?.customerId, uid);
  assert.strictEqual(data?.spendableBalance, 0);
  assert.strictEqual(data?.boncukDebt, 0);
  assert.strictEqual(data?.validOrderEntitlementBoncuk, 0);
  assert.strictEqual(data?.earningCarryNumerator, "0", "a freshly-provisioned zero account has zero carry, canonical form");
  assert.strictEqual(data?.earningCarryDenominator, "1");
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
    validOrderEntitlementBoncuk: 100, // consistent with lifetimeEarned — nothing has ever been reversed.
    earningCarryNumerator: "3", // 3/10 Boncuk — an exact, arbitrary fraction.
    earningCarryDenominator: "10",
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
    // Projected fresh from the exact stored carry (3/10) against the
    // default policy's own block size (1000): floor(3*1000/10)=300,
    // needed=700 — never a currency value read verbatim from storage.
    earningRemainderMinorUnits: 300,
    minorUnitsUntilNextBoncuk: 700,
    lifetimeEarned: 100,
    lifetimeRedeemed: 58,
    policy: {
      earningSpendMinorUnits: 5000,
      earningBoncukAmount: 5,
      redemptionValueMinorUnitsPerBoncuk: 100,
      maxRedemptionBasisPoints: 5000,
    },
  });

  const data = await accountDoc(uid);
  assert.strictEqual(data?.spendableBalance, 42);
  assert.strictEqual(data?.boncukDebt, 9);
  assert.strictEqual(data?.validOrderEntitlementBoncuk, 100, "the O(1) reversal projection must never be touched by a read");
  assert.strictEqual(data?.earningCarryNumerator, "3", "the stored exact carry must never be touched by a read");
  assert.strictEqual(data?.earningCarryDenominator, "10");
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
  // This fixture also predates earningCarryNumerator/earningCarryDenominator
  // entirely (a pre-Fractional-Entitlement-Carry shape). With no exact
  // carry to trust, the projection conservatively treats it as zero rather
  // than reinterpreting the old stored earningRemainderMinorUnits (500)
  // as if it were something it never was — same "never fabricate/
  // reinterpret" discipline as the earning trigger's own legacy handling,
  // applied here for display only.
  assert.strictEqual(body.result?.earningRemainderMinorUnits, 0);
  assert.strictEqual(body.result?.minorUnitsUntilNextBoncuk, 1000);

  const data = await accountDoc(uid);
  assert.strictEqual(data && "boncukDebt" in data, false, "a pure read must never backfill/persist the missing field");
});

// =========================================================================
// E. Configurable Loyalty Economics (2026-08-24) — server-authoritative
// per-organization policy, folded into this callable's response.
// =========================================================================

async function deleteOrgPolicyAndVersion1(organizationId: string) {
  // The immutable `loyaltyPolicyVersions/{organizationId}_1` document must
  // be deleted alongside `loyaltyPolicies/{organizationId}` — leaving it
  // behind makes the resolver's own `tx.create()` (deliberately a create,
  // not a set, for an append-only collection) throw ALREADY_EXISTS the next
  // time this organization is auto-provisioned from scratch.
  //
  // Same-day correction (2026-08-24): the `loyaltyPolicyBootstraps/{organizationId}`
  // marker must ALSO be deleted here. If it were left behind, the next
  // resolution of this organization (by this test file or any other test
  // sharing the emulator) would see "bootstrap exists, but the policy
  // document is missing" and correctly, deliberately, fail closed as
  // `missing-live-policy` instead of re-provisioning — exactly the
  // fail-closed behavior this same-day correction requires in production,
  // but not what this test helper's callers want: they need the canonical
  // org restored to a genuine "never provisioned" state so the next test
  // can freshly auto-provision the locked default again.
  await db().collection("loyaltyPolicies").doc(organizationId).delete();
  await db().collection("loyaltyPolicyVersions").doc(`${organizationId}_1`).delete();
  await db().collection("loyaltyPolicyBootstraps").doc(organizationId).delete();
}

test("a custom (non-default) policy already seeded for the organization is reflected verbatim, never the hardcoded default", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  const policyRef = db().collection("loyaltyPolicies").doc(SINGLE_TENANT_ORGANIZATION_ID);
  const now = admin.firestore.Timestamp.now();
  await policyRef.set({
    organizationId: SINGLE_TENANT_ORGANIZATION_ID,
    earningSpendMinorUnits: 3000,
    earningBoncukAmount: 2,
    redemptionValueMinorUnitsPerBoncuk: 150,
    maxRedemptionBasisPoints: 3000,
    version: 2,
    effectiveAt: now,
    createdAt: now,
    updatedAt: now,
  });

  try {
    const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {}, idToken);
    assert.strictEqual(httpStatus, 200);
    assert.deepStrictEqual(body.result?.policy, {
      earningSpendMinorUnits: 3000,
      earningBoncukAmount: 2,
      redemptionValueMinorUnitsPerBoncuk: 150,
      maxRedemptionBasisPoints: 3000,
    });
    // Internal/administrative fields are never leaked into the customer response.
    assert.strictEqual((body.result?.policy as Record<string, unknown>).version, undefined);
    assert.strictEqual((body.result?.policy as Record<string, unknown>).effectiveAt, undefined);
  } finally {
    // SINGLE_TENANT_ORGANIZATION_ID's own loyaltyPolicies document is shared
    // state across this entire emulator test run (every other test file's
    // default-path assertions resolve the same canonical org) — this test
    // deliberately mutates it, so it MUST restore "no policy provisioned
    // yet" afterward, letting the next caller (in this file or any other)
    // freshly auto-provision the locked default again.
    await deleteOrgPolicyAndVersion1(SINGLE_TENANT_ORGANIZATION_ID);
  }
});

test("a different organization's custom policy never leaks into this organization's response — tenant isolation", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid); // membership in the canonical org only
  const otherOrgPolicyRef = db().collection("loyaltyPolicies").doc("org-2");
  const now = admin.firestore.Timestamp.now();
  // A wildly different policy, seeded for a DIFFERENT organization.
  await otherOrgPolicyRef.set({
    organizationId: "org-2",
    earningSpendMinorUnits: 100000,
    earningBoncukAmount: 1,
    redemptionValueMinorUnitsPerBoncuk: 5000,
    maxRedemptionBasisPoints: 10000,
    version: 1,
    effectiveAt: now,
    createdAt: now,
    updatedAt: now,
  });

  try {
    const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {}, idToken);
    assert.strictEqual(httpStatus, 200);
    // Still the canonical org's own (auto-provisioned default) policy.
    assert.deepStrictEqual(body.result?.policy, {
      earningSpendMinorUnits: 5000,
      earningBoncukAmount: 5,
      redemptionValueMinorUnitsPerBoncuk: 100,
      maxRedemptionBasisPoints: 5000,
    });
  } finally {
    await otherOrgPolicyRef.delete();
  }
});

test("a corrupt policy document (negative earningSpendMinorUnits) fails the whole call closed — never fabricates a rate", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  const policyRef = db().collection("loyaltyPolicies").doc(SINGLE_TENANT_ORGANIZATION_ID);
  const now = admin.firestore.Timestamp.now();
  await policyRef.set({
    organizationId: SINGLE_TENANT_ORGANIZATION_ID,
    // A non-integer-reducible ratio (e.g. 1000/3) is deliberately NOT used
    // as the corruption trigger here — the same-day correction removed the
    // divisibility constraint entirely (5000 -> 3 is now a genuinely
    // supported, exact ratio). A negative value is unambiguously corrupt.
    earningSpendMinorUnits: -1000,
    earningBoncukAmount: 3,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
    version: 1,
    effectiveAt: now,
    createdAt: now,
    updatedAt: now,
  });

  try {
    const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {}, idToken);
    assert.strictEqual(httpStatus, 400, "failed-precondition maps to HTTP 400");
    assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");

    // Never provisions/repairs anything — the corrupt document is untouched.
    const policySnap = await policyRef.get();
    assert.strictEqual(policySnap.data()?.earningSpendMinorUnits, -1000);
  } finally {
    // Same shared-state reasoning as the previous test (including the
    // paired loyaltyPolicyVersions/{org}_1 cleanup) — this canonical
    // org's loyaltyPolicies document must never leak a corrupted state into
    // any other test in this file or any other test file sharing the
    // emulator.
    await deleteOrgPolicyAndVersion1(SINGLE_TENANT_ORGANIZATION_ID);
  }
});

test("MANDATORY (Fractional Entitlement Carry correction): a customer's exact partial-Boncuk carry earned under V1 FULLY SURFACES in the snapshot response under a since-changed V2 policy — never zeroed, never forfeited, never re-rated", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);

  // The correction's own locked example: a customer has earned exactly
  // 0.40 Boncuk of unconverted progress under V1 (5000/5) — carry 2/5.
  const accountRef = db()
    .collection("loyaltyAccounts")
    .doc(`${SINGLE_TENANT_ORGANIZATION_ID}_${uid}`);
  const now = admin.firestore.Timestamp.now();
  await accountRef.set({
    organizationId: SINGLE_TENANT_ORGANIZATION_ID,
    customerId: uid,
    spendableBalance: 2,
    boncukDebt: 0,
    validOrderEntitlementBoncuk: 2,
    earningCarryNumerator: "2",
    earningCarryDenominator: "5",
    lifetimeEarned: 2,
    lifetimeRedeemed: 0,
    createdAt: now,
    updatedAt: now,
    revision: 1,
  });

  // The org's policy has since transitioned to V2, a genuinely different
  // (non-integer-reducible) ratio — 5000 -> 3.
  const policyRef = db().collection("loyaltyPolicies").doc(SINGLE_TENANT_ORGANIZATION_ID);
  await policyRef.set({
    organizationId: SINGLE_TENANT_ORGANIZATION_ID,
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 3,
    redemptionValueMinorUnitsPerBoncuk: 50,
    maxRedemptionBasisPoints: 2500,
    version: 2,
    effectiveAt: now,
    createdAt: now,
    updatedAt: now,
  });

  try {
    const { httpStatus, body } = await callCallable(SNAPSHOT_URL, {}, idToken);
    assert.strictEqual(httpStatus, 200);

    // The stored carry (2/5, earned under V1) is projected AS-IS against
    // V2's own block size (1667): floor(2*1667/5)=666, needed=1001. It is
    // NEVER zeroed, NEVER discarded, and NEVER reinterpreted as if it had
    // been earned at V2's own ratio (that would be re-rating, forbidden).
    assert.strictEqual(
      body.result?.earningRemainderMinorUnits,
      666,
      "the V1-earned carry must fully surface, projected against V2's own block size — never zeroed",
    );
    assert.strictEqual(body.result?.minorUnitsUntilNextBoncuk, 1001);
    assert.strictEqual(body.result?.spendableBalance, 2);
    assert.strictEqual(body.result?.lifetimeEarned, 2);
    assert.deepStrictEqual(body.result?.policy, {
      earningSpendMinorUnits: 5000,
      earningBoncukAmount: 3,
      redemptionValueMinorUnitsPerBoncuk: 50,
      maxRedemptionBasisPoints: 2500,
    });

    // OLD_PROGRESS_AUDIT_PRESERVED: a pure read must never mutate the
    // account — the exact carry earned under V1 stays exactly as it was
    // in storage, byte-for-byte.
    const data = await accountDoc(uid);
    assert.strictEqual(data?.validOrderEntitlementBoncuk, 2);
    assert.strictEqual(data?.earningCarryNumerator, "2");
    assert.strictEqual(data?.earningCarryDenominator, "5");
    assert.strictEqual(data?.spendableBalance, 2);
    assert.strictEqual(data?.revision, 1, "a pure read must never bump revision");
  } finally {
    await deleteOrgPolicyAndVersion1(SINGLE_TENANT_ORGANIZATION_ID);
  }
});

test("the policy can never be supplied/overridden by the client — arbitrary request data is ignored", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);

  const { httpStatus, body } = await callCallable(
    SNAPSHOT_URL,
    { policy: { earningSpendMinorUnits: 1, earningBoncukAmount: 1000000 } },
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result?.policy, {
    earningSpendMinorUnits: 5000,
    earningBoncukAmount: 5,
    redemptionValueMinorUnitsPerBoncuk: 100,
    maxRedemptionBasisPoints: 5000,
  });
});
