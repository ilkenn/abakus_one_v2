import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-3 — the deterministic, emulator-backed end-to-end flow tying together
 * every backend increment built across this phase's waves, in one coherent
 * scenario, through `readyForPayment`:
 *
 *  1. A table session is opened (mirrors what a real QR scan produces —
 *     `openTableGuestSession` itself is exercised by its own dedicated test
 *     files; this test seeds the equivalent state directly, the same
 *     established convention `submitDineInOrder.test.ts` uses).
 *  2. Two customers receive separate guest sub-accounts at the same table.
 *  3. Both submit independently (`submitDineInOrder`, guestSession mode).
 *  4. The cashier accepts guest 1's line and proposes a replacement for
 *     guest 2's line (`respondToDineInOrderLines` / `dineInCounterProposal`).
 *  5. Guest 2 accepts the replacement (`respondToDineInCounterProposal`).
 *  6. The cashier adds a staff-entered product onto guest 1's own
 *     sub-account (`submitDineInOrder`, staffEntry mode).
 *  7. The check is split using two representative modes — by customer
 *     (guest 2) and by product (one of guest 1's two lines) — leaving one
 *     line deliberately unsplit to prove a partial split still finalizes
 *     correctly once every line itself is decided.
 *  8. The table is transferred to a second physical table
 *     (`transferTableSession`) — the check/allocations/orders all continue
 *     to resolve correctly afterward via the unchanged `TableSession.id`.
 *  9. The check reaches `readyForPayment` (`finalizeCheckReadyForPayment`)
 *     — AP-3's own stated boundary; this test never claims `paid`/`settled`.
 * 10. Every mutation above went through a real callable under a real
 *     staff/customer identity — no direct Admin-SDK document write ever
 *     substitutes for a client-authoritative action anywhere in this flow
 *     (only fixture/seed setup uses the Admin SDK directly, and that setup
 *     is called out explicitly below).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;

const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const REQUEST_DEVICE_REGISTRATION_URL = fn("requestDeviceRegistration");
const REQUEST_CHALLENGE_URL = fn("requestDeviceChallenge");
const ISSUE_SESSION_URL = fn("issueDeviceSession");
const RESPOND_APPROVAL_URL = fn("respondToApprovalRequest");
const SUBMIT_DINE_IN_URL = fn("submitDineInOrder");
const RESPOND_LINES_URL = fn("respondToDineInOrderLines");
const PROPOSE_REPLACEMENT_URL = fn("proposeDineInLineReplacement");
const RESPOND_PROPOSAL_URL = fn("respondToDineInCounterProposal");
const OPEN_CHECK_URL = fn("openCheck");
const SPLIT_BY_CUSTOMER_URL = fn("splitCheckByCustomer");
const SPLIT_BY_PRODUCT_URL = fn("splitCheckByProduct");
const FINALIZE_CHECK_URL = fn("finalizeCheckReadyForPayment");
const TRANSFER_TABLE_URL = fn("transferTableSession");

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
let idCounter = 0;
function nextId(prefix: string): string { idCounter += 1; return `${prefix}-${TEST_RUN_ID}-${idCounter}`; }

async function seedTenant() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false });
  await db().collection("entitlements").doc(`${organizationId}_organization_${organizationId}_pos`).set({
    organizationId, scopeType: "organization", scopeId: organizationId, module: "pos", status: "active", version: 1,
  });
  return { organizationId, restaurantId, branchId };
}
async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, priceMinorUnits = 10000) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId: "cat_standard", name: `Test Product ${id}`,
    basePriceMinorUnits: priceMinorUnits, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
  });
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
function generateDeviceKeyPair() {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
    sign: (nonce: string) => cryptoSign(null, Buffer.from(nonce, "utf8"), privateKey).toString("base64"),
  };
}
async function activeDeviceSession(organizationId: string, branchId: string, staff: { idToken: string; uid: string }, approver: { idToken: string }) {
  const device = generateDeviceKeyPair();
  const reg = await callCallable(REQUEST_DEVICE_REGISTRATION_URL, { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] }, staff.idToken);
  assert.strictEqual(reg.httpStatus, 200, JSON.stringify(reg.body));
  const deviceId = reg.body.result?.deviceId as string;
  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: reg.body.result?.approvalRequestId, decision: "approved" }, approver.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));
  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  const signature = device.sign(challenge.body.result?.nonce as string);
  const session = await callCallable(ISSUE_SESSION_URL, { organizationId, branchId, deviceId, challengeId: challenge.body.result?.challengeId, signature }, staff.idToken);
  assert.strictEqual(session.httpStatus, 200, JSON.stringify(session.body));
  return { deviceId, deviceSessionId: session.body.result?.sessionId as string };
}

/** Seeds a table's active session + one guest's `tableGuestSessions`/`guestSubAccounts` pair — mirrors `submitDineInOrder.test.ts`'s own `seedTableGuestSession`, extended to return the real `TableSession.id` too (needed by `openCheck`/`transferTableSession`, which `submitDineInOrder`'s own test file never needed to return). */
async function seedGuestAtTable(
  chain: { organizationId: string; restaurantId: string; branchId: string },
  tableId: string,
  guestAuthUid: string,
  existingTableSessionId?: string,
): Promise<{ guestSessionId: string; tableSessionId: string }> {
  const tableSessionId = existingTableSessionId ?? nextId("tsess");
  if (!existingTableSessionId) {
    await db().collection("restaurantTables").doc(tableId).set(
      { organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId, activeTableSessionId: tableSessionId, isActive: true, status: "occupied" },
      { merge: true },
    );
    await db().collection("tableSessions").doc(tableSessionId).set({
      organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId, tableId,
      status: "active", openedAt: admin.firestore.Timestamp.now(), closedAt: null,
      openedByType: "guestQrScan", openedByStaffUid: null, transferredFromTableId: null, version: 1,
    });
  }
  const guestSessionId = nextId("tgs");
  await db().collection("tableGuestSessions").doc(guestSessionId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId, tableId, tableSessionId,
    guestAuthUid, status: "active", createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 6 * 60 * 60 * 1000)),
    lastActivityAt: admin.firestore.Timestamp.now(), qrTokenId: nextId("qrtoken"), reservationContextId: null,
  });
  const subAccountId = `subaccount-${tableSessionId}-${guestAuthUid}`;
  await db().collection("guestSubAccounts").doc(subAccountId).set({
    organizationId: chain.organizationId, branchId: chain.branchId, tableSessionId,
    ownerType: "guestSession", ownerSessionRef: `tableGuestSessions/${guestSessionId}`, ownerAuthUid: guestAuthUid,
    displayName: `Guest ${guestAuthUid.slice(0, 6)}`, status: "open", createdAt: admin.firestore.Timestamp.now(),
    createdByStaffUid: null, version: 1,
  });
  return { guestSessionId, tableSessionId };
}
function subAccountIdFor(tableSessionId: string, guestAuthUid: string) {
  return `subaccount-${tableSessionId}-${guestAuthUid}`;
}
async function seedFreeTable(organizationId: string, restaurantId: string, branchId: string, tableId: string) {
  await db().collection("restaurantTables").doc(tableId).set({ organizationId, restaurantId, branchId, activeTableSessionId: null, isActive: true, status: "available" });
}

test("AP-3 E2E: QR table session -> two guest sub-accounts -> accept/propose/accept -> staff-added line -> split by customer and by product -> table transfer -> readyForPayment", async () => {
  // --- Fixture: tenant, staff, device session, catalog -------------------
  const chain = await seedTenant();
  const admin1 = await bootstrapRealAdmin(chain.organizationId);
  const staff = await newStaffMember(chain.organizationId, chain.branchId, admin1.idToken, "staff");
  const { deviceId, deviceSessionId } = await activeDeviceSession(chain.organizationId, chain.branchId, staff, admin1);
  const productA = nextId("product");
  const productB = nextId("product");
  await seedMenuProduct(productA, chain.restaurantId, chain.organizationId, 10000);
  await seedMenuProduct(productB, chain.restaurantId, chain.organizationId, 8000);

  // --- 1/2. QR opens a table session; two guests receive separate sub-accounts.
  const sourceTableId = nextId("table");
  const guest1 = await signUpAnonymously();
  const guest2 = await signUpAnonymously();
  const g1 = await seedGuestAtTable(chain, sourceTableId, guest1.uid);
  const g2 = await seedGuestAtTable(chain, sourceTableId, guest2.uid, g1.tableSessionId);
  assert.strictEqual(g1.tableSessionId, g2.tableSessionId, "both guests share the same physical table's session");

  // --- 3. Both submit independently.
  const order1 = await callCallable(SUBMIT_DINE_IN_URL, {
    mode: "guestSession", submissionKey: nextId("key"), tableSessionId: g1.guestSessionId,
    items: [{ kind: "product", productId: productA, quantity: 1 }],
    guestDisplayName: "Ayşe",
  }, guest1.idToken);
  assert.strictEqual(order1.httpStatus, 200, JSON.stringify(order1.body));
  const order1Id = order1.body.result!.orderId as string;

  const order2 = await callCallable(SUBMIT_DINE_IN_URL, {
    mode: "guestSession", submissionKey: nextId("key"), tableSessionId: g2.guestSessionId,
    items: [{ kind: "product", productId: productA, quantity: 1 }],
    guestDisplayName: "Mehmet",
  }, guest2.idToken);
  assert.strictEqual(order2.httpStatus, 200, JSON.stringify(order2.body));
  const order2Id = order2.body.result!.orderId as string;

  // --- 4a. Cashier accepts guest 1's line.
  const acceptLine = await callCallable(RESPOND_LINES_URL, {
    orderId: order1Id, decisions: [{ lineIndex: 0, decision: "accept" }],
  }, staff.idToken);
  assert.strictEqual(acceptLine.httpStatus, 200, JSON.stringify(acceptLine.body));
  assert.strictEqual(acceptLine.body.result?.linesDispositionSummary, "resolved");

  // --- 4b. Cashier proposes a replacement for guest 2's line.
  const propose = await callCallable(PROPOSE_REPLACEMENT_URL, {
    organizationId: chain.organizationId, branchId: chain.branchId, deviceId, deviceSessionId,
    orderId: order2Id, lineIndex: 0, proposedProductId: productB, proposedQuantity: 1,
    reasonCode: "outOfStock", reasonMessage: "Seçtiğiniz ürün tükendi, bu ürünü öneriyoruz.",
  }, staff.idToken);
  assert.strictEqual(propose.httpStatus, 200, JSON.stringify(propose.body));

  // --- 5. Guest 2 accepts the replacement.
  const acceptProposal = await callCallable(RESPOND_PROPOSAL_URL, {
    orderId: order2Id, lineIndex: 0, decision: "accept",
  }, guest2.idToken);
  assert.strictEqual(acceptProposal.httpStatus, 200, JSON.stringify(acceptProposal.body));
  assert.strictEqual(acceptProposal.body.result?.status, "accepted");

  const order2AfterAccept = (await db().collection("orders").doc(order2Id).get()).data()!;
  assert.strictEqual(order2AfterAccept.lines[0].status, "accepted");
  assert.strictEqual(order2AfterAccept.lines[0].productId, productB, "the accepted replacement's product is applied exactly as proposed");

  // --- 6. Cashier adds a staff-entered product onto guest 1's own sub-account.
  const staffEntry = await callCallable(SUBMIT_DINE_IN_URL, {
    mode: "staffEntry", submissionKey: nextId("key"),
    organizationId: chain.organizationId, branchId: chain.branchId, tableId: sourceTableId,
    deviceId, deviceSessionId,
    subAccountSelection: { mode: "existingSubAccount", subAccountId: subAccountIdFor(g1.tableSessionId, guest1.uid) },
    items: [{ kind: "product", productId: productA, quantity: 1 }],
  }, staff.idToken);
  assert.strictEqual(staffEntry.httpStatus, 200, JSON.stringify(staffEntry.body));
  const staffEntryOrderId = staffEntry.body.result!.orderId as string;
  const staffEntryOrder = (await db().collection("orders").doc(staffEntryOrderId).get()).data()!;
  assert.strictEqual(staffEntryOrder.lines[0].status, "accepted", "a staff-entered line is pre-accepted — a trusted, device-checked staff entry IS the approval");

  // --- 7a. Open the check.
  const openCheckRes = await callCallable(OPEN_CHECK_URL, {
    organizationId: chain.organizationId, branchId: chain.branchId, deviceId, deviceSessionId,
    tableSessionId: g1.tableSessionId,
  }, staff.idToken);
  assert.strictEqual(openCheckRes.httpStatus, 200, JSON.stringify(openCheckRes.body));
  const checkId = openCheckRes.body.result!.checkId as string;

  // --- 7b. Split by customer — guest 2's now-replaced line.
  const splitByCustomer = await callCallable(SPLIT_BY_CUSTOMER_URL, {
    organizationId: chain.organizationId, branchId: chain.branchId, deviceId, deviceSessionId,
    checkId, subAccountId: subAccountIdFor(g1.tableSessionId, guest2.uid),
  }, staff.idToken);
  assert.strictEqual(splitByCustomer.httpStatus, 200, JSON.stringify(splitByCustomer.body));

  // --- 7c. Split by product — guest 1's original line (the staff-added line is left unsplit deliberately, proving a check with more than one still-unallocated accepted line among its source orders can still finalize as long as no line is UNDECIDED).
  const splitByProduct = await callCallable(SPLIT_BY_PRODUCT_URL, {
    organizationId: chain.organizationId, branchId: chain.branchId, deviceId, deviceSessionId,
    checkId, subAccountId: subAccountIdFor(g1.tableSessionId, guest1.uid),
    sourceOrderId: order1Id, sourceLineIndex: 0,
  }, staff.idToken);
  assert.strictEqual(splitByProduct.httpStatus, 200, JSON.stringify(splitByProduct.body));

  // --- 8. Table transfer — the check/orders continue to resolve correctly afterward via the unchanged TableSession.id.
  const targetTableId = nextId("table");
  await seedFreeTable(chain.organizationId, chain.restaurantId, chain.branchId, targetTableId);
  const transfer = await callCallable(TRANSFER_TABLE_URL, {
    organizationId: chain.organizationId, branchId: chain.branchId, deviceId, deviceSessionId,
    sourceTableId, targetTableId,
  }, staff.idToken);
  assert.strictEqual(transfer.httpStatus, 200, JSON.stringify(transfer.body));
  const sourceTableAfter = (await db().collection("restaurantTables").doc(sourceTableId).get()).data()!;
  const targetTableAfter = (await db().collection("restaurantTables").doc(targetTableId).get()).data()!;
  assert.strictEqual(sourceTableAfter.activeTableSessionId, null);
  assert.strictEqual(targetTableAfter.activeTableSessionId, g1.tableSessionId);

  // --- 9. Finalize — readyForPayment. AP-3 stops here; never `paid`/`settled`.
  const finalize = await callCallable(FINALIZE_CHECK_URL, {
    organizationId: chain.organizationId, branchId: chain.branchId, deviceId, deviceSessionId,
    checkId,
  }, staff.idToken);
  assert.strictEqual(finalize.httpStatus, 200, JSON.stringify(finalize.body));
  assert.strictEqual(finalize.body.result?.status, "readyForPayment");

  const finalCheck = (await db().collection("checks").doc(checkId).get()).data()!;
  assert.strictEqual(finalCheck.status, "readyForPayment");
  assert.notStrictEqual(finalCheck.readyForPaymentAt, null);

  // --- 10. No client-authoritative write occurred anywhere in this flow —
  // every state change above was produced by a real callable under a real
  // staff/customer identity, never a direct client Firestore write (the
  // Admin SDK usage in this test file is confined to fixture SEEDING —
  // `seedTenant`/`seedMenuProduct`/`seedGuestAtTable`/`seedFreeTable` — and
  // to the read-only assertions above, never to a mutation the real app
  // would need to perform itself).
});
