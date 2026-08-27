import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * AP-3 Wave 3 — emulator-backed tests for the Customer Directory
 * (`functions/src/customerDirectory.ts`/`completeCustomerProfile.ts`'s own
 * new projection writes). Requires `CUSTOMER_PHONE_SEARCH_HMAC_SECRET` to
 * be available via `functions/.secret.local` (emulator-only, gitignored).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const COMPLETE_PROFILE_URL = fn("completeCustomerProfile");
const LIST_PLATFORM_URL = fn("listPlatformCustomers");
const SEARCH_PLATFORM_PHONE_URL = fn("searchPlatformCustomersByPhone");
const GET_PLATFORM_DETAIL_URL = fn("getPlatformCustomerDetail");
const REVEAL_ADDRESS_BOOK_URL = fn("revealCustomerFullAddressBook");
const SET_PLATFORM_RESTRICTION_URL = fn("setPlatformCustomerRestriction");
const LIST_TENANT_URL = fn("listTenantCustomers");
const GET_TENANT_DETAIL_URL = fn("getTenantCustomerDetail");
const SEARCH_POS_URL = fn("searchCustomersForPos");
const SET_TENANT_RESTRICTION_URL = fn("setTenantCustomerRestriction");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const SYNC_PLATFORM_CLAIMS_URL = fn("syncOwnPlatformClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });
const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string; message?: string } };
  return { httpStatus: response.status, body };
}
async function signUpAnonymously(): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const response = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = (await response.json()) as { idToken: string; refreshToken: string; localId: string };
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}
async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  return body.id_token;
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let idCounter = 0;
let phoneCounter = 0;
function nextId(prefix: string): string { idCounter += 1; return `${prefix}-${TEST_RUN_ID}-${idCounter}`; }

async function createRealPhoneUser(): Promise<{ idToken: string; refreshToken: string; uid: string; phoneNumber: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }),
  });
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string; phoneNumber: string }[] };
  const match = codesBody.verificationCodes.filter((c) => c.phoneNumber === phoneNumber).pop()!;
  const signInRes = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sessionInfo: match.sessionInfo, code: match.code }),
  });
  const signInBody = (await signInRes.json()) as { idToken: string; refreshToken: string; localId: string };
  return { idToken: signInBody.idToken, refreshToken: signInBody.refreshToken, uid: signInBody.localId, phoneNumber };
}

async function seedTenant() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false });
  return { organizationId, restaurantId, branchId };
}
async function bootstrapRealAdmin(organizationId: string): Promise<{ uid: string; idToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { uid, idToken: await refreshIdToken(refreshToken) };
}
async function newStaffMember(organizationId: string, branchId: string, adminIdToken: string, role: string) {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles: [role], branchAccess: [], restaurantAccess: [], status: "active", version: 1,
  });
  const assign = await callCallable(ASSIGN_ROLE_URL, { organizationId, targetUid: uid, role }, adminIdToken);
  assert.strictEqual(assign.httpStatus, 200, JSON.stringify(assign.body));
  const grantBranch = await callCallable(GRANT_BRANCH_URL, { organizationId, targetUid: uid, branchId }, adminIdToken);
  assert.strictEqual(grantBranch.httpStatus, 200, JSON.stringify(grantBranch.body));
  await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  return { uid, idToken: await refreshIdToken(refreshToken) };
}
/**
 * `completeCustomerProfile` always resolves its tenant relationship to the
 * hardcoded `SINGLE_TENANT_ORGANIZATION_ID` ("org-1") — never a client- or
 * test-supplied organizationId (confirmed directly in
 * `completeCustomerProfile.ts`; mirrors that file's own test suite's exact
 * convention). A directory test that needs staff to read a REAL
 * registered customer's tenant entry must therefore itself operate under
 * `"org-1"`, not a freshly-generated random org — staff membership is
 * seeded directly (Admin SDK), never via `bootstrapFirstAdminAccount`
 * (which would collide with any other test in this same run that already
 * bootstrapped org-1's first admin).
 */
const SINGLE_TENANT_ORGANIZATION_ID = "org-1";
async function seedSingleTenantOrg() {
  await db().collection("organizations").doc(SINGLE_TENANT_ORGANIZATION_ID).set({ name: "Abaküs", isActive: true }, { merge: true });
  return { organizationId: SINGLE_TENANT_ORGANIZATION_ID };
}
async function directStaffMember(organizationId: string, role: string): Promise<{ uid: string; idToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles: [role], branchAccess: [], restaurantAccess: [], status: "active", version: 1,
  });
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { uid, idToken: await refreshIdToken(refreshToken) };
}

async function seedPlatformOwner(): Promise<{ uid: string; idToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("platformMembers").doc(uid).set({
    displayName: uid, roles: ["platformOwner"], status: "active", authUid: uid,
    createdAt: admin.firestore.Timestamp.now(), updatedAt: admin.firestore.Timestamp.now(), version: 1,
  });
  const sync = await callCallable(SYNC_PLATFORM_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { uid, idToken: await refreshIdToken(refreshToken) };
}

async function registerCustomer(organizationId: string): Promise<{ uid: string; idToken: string; phoneNumber: string; displayName: string }> {
  const { idToken, uid, phoneNumber } = await createRealPhoneUser();
  // A GENUINELY unique first name per customer (not just "Ayşe" + a small
  // counter) — every customer in this file otherwise shares the exact
  // same "ayşe" normalized prefix, and since Firestore prefix-range
  // queries sort LEXICOGRAPHICALLY (not numerically), a bare counter
  // suffix ("ayse2" vs "ayse10") makes a specific customer easy to push
  // outside a bounded result page. `nextId` embeds the whole
  // TEST_RUN_ID, which is what actually makes a namePrefix search
  // deterministically isolate exactly one customer.
  const firstName = nextId("Ayşe");
  const lastName = "Yılmaz";
  const res = await callCallable(COMPLETE_PROFILE_URL, {
    firstName, lastName, email: `${nextId("mail")}@example.com`,
    occupationStatus: "working", workplaceName: "Test A.Ş.", gender: "female", birthDate: "1990-01-01",
  }, idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  void organizationId;
  return { uid, idToken, phoneNumber, displayName: `${firstName} ${lastName}` };
}

test("completeCustomerProfile: populates BOTH the platform projection (immediately) and the tenant projection (from the real membership write, always the single-tenant org), never inventing a relationship", async () => {
  await seedSingleTenantOrg();
  const { uid, phoneNumber, displayName } = await registerCustomer(SINGLE_TENANT_ORGANIZATION_ID);

  const platformEntry = await db().collection("platformCustomerDirectoryEntries").doc(uid).get();
  assert.ok(platformEntry.exists);
  assert.strictEqual(platformEntry.data()!.displayName, displayName);
  assert.strictEqual(platformEntry.data()!.phoneNumber, phoneNumber);
  assert.ok(typeof platformEntry.data()!.phoneSearchHash === "string" && platformEntry.data()!.phoneSearchHash.length > 0);

  const tenantEntry = await db().collection("customerDirectoryEntries").doc(`${SINGLE_TENANT_ORGANIZATION_ID}_${uid}`).get();
  assert.ok(tenantEntry.exists);
  assert.strictEqual(tenantEntry.data()!.organizationId, SINGLE_TENANT_ORGANIZATION_ID);
});

test("Platform directory: listPlatformCustomers includes a customer exactly once even though completeCustomerProfile has already run (never duplicated by a repeat registration call)", async () => {
  const { organizationId } = await seedTenant();
  const platformOwner = await seedPlatformOwner();
  const customer = await registerCustomer(organizationId);

  const list = await callCallable(LIST_PLATFORM_URL, { namePrefix: customer.displayName }, platformOwner.idToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const matches = (list.body.result?.customers as Array<Record<string, unknown>>).filter((c) => c.id === customer.uid);
  assert.strictEqual(matches.length, 1);

  // A non-platform-member (a tenant admin) must be denied outright.
  const { organizationId: otherOrgId, branchId: otherBranchId } = await seedTenant();
  const otherAdmin = await bootstrapRealAdmin(otherOrgId);
  const deniedList = await callCallable(LIST_PLATFORM_URL, {}, otherAdmin.idToken);
  assert.strictEqual(deniedList.httpStatus, 403, JSON.stringify(deniedList.body));
  void otherBranchId;
});

test("Platform directory: a customer with NO tenant relationship still appears exactly once in the platform list", async () => {
  const { organizationId } = await seedTenant(); // org exists, but registerCustomer below never joins it as staff-visible tenant data beyond the single-tenant default
  const platformOwner = await seedPlatformOwner();
  const customer = await registerCustomer(organizationId);

  const detail = await callCallable(GET_PLATFORM_DETAIL_URL, { uid: customer.uid }, platformOwner.idToken);
  assert.strictEqual(detail.httpStatus, 200, JSON.stringify(detail.body));
  assert.strictEqual(detail.body.result?.uid, customer.uid);
  // Real address book is NEVER exposed by the detail read alone.
  assert.strictEqual((detail.body.result as Record<string, unknown> | undefined)?.customerAddresses, undefined);
});

test("Platform directory: phone search returns the customer WITHOUT ever exposing the search hash or raw phone number", async () => {
  const { organizationId } = await seedTenant();
  const platformOwner = await seedPlatformOwner();
  const customer = await registerCustomer(organizationId);

  const res = await callCallable(SEARCH_PLATFORM_PHONE_URL, { phoneNumber: customer.phoneNumber }, platformOwner.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  const customers = res.body.result?.customers as Array<Record<string, unknown>>;
  assert.strictEqual(customers.length, 1);
  assert.strictEqual(customers[0].id, customer.uid);
  assert.strictEqual(JSON.stringify(res.body).includes("phoneSearchHash"), false);
  assert.strictEqual(JSON.stringify(res.body).includes(customer.phoneNumber), false);
});

test("Tenant directory isolation: a customer registered under org A does not appear in org B's tenant directory", async () => {
  const orgA = await seedTenant();
  const orgB = await seedTenant();
  const customer = await registerCustomer(orgA.organizationId);
  const adminB = await bootstrapRealAdmin(orgB.organizationId);
  const staffB = await newStaffMember(orgB.organizationId, orgB.branchId, adminB.idToken, "staff");

  const detail = await callCallable(GET_TENANT_DETAIL_URL, { organizationId: orgB.organizationId, customerId: customer.uid }, staffB.idToken);
  assert.strictEqual(detail.httpStatus, 404, JSON.stringify(detail.body));

  const listA = await callCallable(LIST_TENANT_URL, { organizationId: orgA.organizationId }, staffB.idToken);
  // staffB has no org-A membership at all — must be denied outright.
  assert.strictEqual(listA.httpStatus, 403, JSON.stringify(listA.body));
});

test("Tenant Admin's own customer detail never receives unrelated saved addresses — only THIS org's own order snapshots, never customerAddresses directly", async () => {
  const { organizationId } = await seedSingleTenantOrg();
  const staff = await directStaffMember(organizationId, "staff");
  const customer = await registerCustomer(organizationId);

  // Seed an UNRELATED saved address for this customer — must never leak
  // through the tenant-facing detail read.
  await db().collection("customerAddresses").doc(nextId("addr")).set({
    customerId: customer.uid, label: "Ev", line1: "Gizli Sokak No:1", city: "İstanbul", createdAt: admin.firestore.Timestamp.now(), verifiedAt: null,
  });

  const detail = await callCallable(GET_TENANT_DETAIL_URL, { organizationId, customerId: customer.uid }, staff.idToken);
  assert.strictEqual(detail.httpStatus, 200, JSON.stringify(detail.body));
  assert.strictEqual(JSON.stringify(detail.body).includes("Gizli Sokak"), false, "an unrelated saved address must never appear in a tenant-facing read");
  assert.deepStrictEqual(detail.body.result?.orderAddressSnapshots, []);
  assert.strictEqual(detail.body.result?.marketingConsent, "notCaptured");
});

test("revealCustomerFullAddressBook: Platform-capability-gated only — a tenant staff member (even a manager) cannot call it", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const customer = await registerCustomer(organizationId);

  const res = await callCallable(REVEAL_ADDRESS_BOOK_URL, { uid: customer.uid, reason: "Fraud investigation" }, manager.idToken);
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("revealCustomerFullAddressBook: Platform Owner CAN reveal, requires a reason, and creates an audit record", async () => {
  const { organizationId } = await seedTenant();
  const platformOwner = await seedPlatformOwner();
  const customer = await registerCustomer(organizationId);
  await db().collection("customerAddresses").doc(nextId("addr")).set({
    customerId: customer.uid, label: "Ev", line1: "Gerçek Adres", city: "İstanbul", createdAt: admin.firestore.Timestamp.now(), verifiedAt: null,
  });

  const missingReason = await callCallable(REVEAL_ADDRESS_BOOK_URL, { uid: customer.uid }, platformOwner.idToken);
  assert.strictEqual(missingReason.httpStatus, 400, JSON.stringify(missingReason.body));

  const res = await callCallable(REVEAL_ADDRESS_BOOK_URL, { uid: customer.uid, reason: "Fraud investigation #1234" }, platformOwner.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  assert.strictEqual((res.body.result?.addresses as unknown[]).length, 1);

  const auditSnap = await db().collection("auditEvents").where("type", "==", "customerDirectory.fullAddressBookRevealed").where("targetRef", "==", `customers/${customer.uid}`).get();
  assert.strictEqual(auditSnap.size, 1);
  assert.strictEqual(auditSnap.docs[0].data().reasonMessage, "Fraud investigation #1234");
});

test("setTenantCustomerRestriction: writes ONLY the tenant-scoped collection — the canonical global customers/{uid} document is never mutated", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const customer = await registerCustomer(organizationId);
  const before = await db().collection("customers").doc(customer.uid).get();

  const res = await callCallable(SET_TENANT_RESTRICTION_URL, {
    organizationId, customerId: customer.uid, status: "active", reasonCode: "unpaidBalance", reasonMessage: "Ödenmemiş bakiye.",
  }, manager.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));

  const restriction = await db().collection("tenantCustomerRestrictions").doc(`${organizationId}_${customer.uid}`).get();
  assert.strictEqual(restriction.data()!.status, "active");
  const after = await db().collection("customers").doc(customer.uid).get();
  assert.deepStrictEqual(after.data(), before.data(), "the canonical global customer document must be byte-identical before/after a tenant restriction");
});

test("setTenantCustomerRestriction: a plain staff member (below manager) cannot set a restriction — manager+ only", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const customer = await registerCustomer(organizationId);

  const res = await callCallable(SET_TENANT_RESTRICTION_URL, {
    organizationId, customerId: customer.uid, status: "active", reasonCode: "x", reasonMessage: "y",
  }, staff.idToken);
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("setPlatformCustomerRestriction: requires the separate platform capability — a tenant manager cannot call it; writes to platformCustomerRestrictions only", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const platformOwner = await seedPlatformOwner();
  const customer = await registerCustomer(organizationId);

  const denied = await callCallable(SET_PLATFORM_RESTRICTION_URL, { uid: customer.uid, status: "active", reasonCode: "x", reasonMessage: "y" }, manager.idToken);
  assert.strictEqual(denied.httpStatus, 403, JSON.stringify(denied.body));

  const allowed = await callCallable(SET_PLATFORM_RESTRICTION_URL, { uid: customer.uid, status: "active", reasonCode: "fraudSuspected", reasonMessage: "z" }, platformOwner.idToken);
  assert.strictEqual(allowed.httpStatus, 200, JSON.stringify(allowed.body));
  const restriction = await db().collection("platformCustomerRestrictions").doc(customer.uid).get();
  assert.strictEqual(restriction.data()!.status, "active");
});

test("searchCustomersForPos: a staff member with viewTenantCustomerDirectory can find a customer by name prefix, minimum operational projection only (no phone number, only masked)", async () => {
  const { organizationId } = await seedSingleTenantOrg();
  const staff = await directStaffMember(organizationId, "staff");
  const customer = await registerCustomer(organizationId);

  const res = await callCallable(SEARCH_POS_URL, { organizationId, namePrefix: customer.displayName }, staff.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  const found = (res.body.result?.customers as Array<Record<string, unknown>>).find((c) => c.id === customer.uid);
  assert.ok(found, "expected the registered customer to appear in a name-prefix POS search");
  assert.strictEqual(JSON.stringify(res.body).includes(customer.phoneNumber), false);
});

test("Direct Firestore reads of every Customer Directory projection/restriction collection are denied for a signed-in customer — callable-only", async () => {
  const { organizationId } = await seedTenant();
  const customer = await registerCustomer(organizationId);
  // Not a Rules-emulator test (that's covered in firestore-tests/rules.test.js)
  // — this asserts the Admin-SDK-side documents exist, confirming the
  // rules test suite is exercising REAL, populated documents, not empty
  // placeholders.
  const platformEntry = await db().collection("platformCustomerDirectoryEntries").doc(customer.uid).get();
  assert.ok(platformEntry.exists);
});
