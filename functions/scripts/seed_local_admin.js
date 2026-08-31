/**
 * Deterministic local-emulator seed for reproducing a real staff/platform
 * sign-in on a developer machine — AP-3 closure tooling. NOT deployed, NOT
 * part of the Functions build (tsconfig.json only includes `src/**\/*.ts`,
 * so this file is invisible to `npm run build`), and refuses outright to
 * run against anything but a local emulator.
 *
 * Every identity/document this script creates is synthetic: fixed test
 * emails under the `abakus.test` domain, a fixed test password, and
 * deterministic ids scoped under one run id. No production project is ever
 * touched — see the refusal check immediately below main().
 *
 * Usage (from the `functions/` directory, with the emulators already
 * running — see `docs/local_admin_login_runbook.md` for the full, verified
 * command sequence):
 *
 *   node scripts/seed_local_admin.js
 *
 * Safe to rerun — every write is either idempotent (deterministic doc ids,
 * `.set()` not `.create()`) or explicitly tolerant of "already exists"
 * (email sign-up falls back to sign-in; bootstrap tolerates an
 * already-bootstrapped organization; guest identities use a deterministic
 * Admin-SDK-created uid, tolerant of `auth/uid-already-exists`, rather than
 * the anonymous sign-up endpoint's always-random uid — see
 * `getOrCreateDeterministicGuestUser` below and
 * `seed_local_admin.idempotency.test.mjs`, which proves this directly:
 * run the seed 3 times against a fresh emulator, assert the exact same 3
 * `guestSubAccounts` document ids every time).
 *
 * Local full-access review account (2026-08-31): `yonetici@abakus.test`
 * (the already-bootstrapped tenant `admin`, org-1/branch-ap3vis) also
 * receives real `platformMembers` `platformOwner` membership under the
 * SAME uid — a fixed-doc-id `.set()`, naturally idempotent exactly like
 * the pre-existing `sahip@abakus.test` grant it mirrors. No parallel/
 * simulated permission system; this is the same canonical membership model
 * every other identity in this script already goes through.
 */
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';

const admin = require('firebase-admin');

const PROJECT_ID = 'abakus-one-dev'; // matches lib/core/config/app_environment_config.dart's `development.firebaseProjectId` — the real Flutter app must be seeded under the SAME project id it initializes with.
const FUNCTIONS_HOST = 'http://127.0.0.1:5001';
const AUTH_HOST = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
const fn = (name) => `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/${name}`;

function refuseUnlessEmulator() {
  const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST || '';
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || '';
  const isLocal = (h) => h.startsWith('127.0.0.1:') || h.startsWith('localhost:');
  if (!isLocal(firestoreHost) || !isLocal(authHost)) {
    console.error(
      'REFUSING TO RUN: FIRESTORE_EMULATOR_HOST/FIREBASE_AUTH_EMULATOR_HOST ' +
        'must both point at a local emulator (127.0.0.1:*/localhost:*). ' +
        `Got FIRESTORE_EMULATOR_HOST="${firestoreHost}" ` +
        `FIREBASE_AUTH_EMULATOR_HOST="${authHost}". This script will never ` +
        'run against a real project, on purpose.',
    );
    process.exit(1);
  }
}
refuseUnlessEmulator();

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

async function callCallable(url, data, idToken) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: 'POST', headers, body: JSON.stringify({ data }) });
  const body = await response.json();
  if (!response.ok || body.error) {
    throw new Error(`${url} failed (${response.status}): ${JSON.stringify(body)}`);
  }
  return body.result;
}

async function createEmailPasswordUser(email, password, displayName) {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, displayName, returnSecureToken: true }),
    },
  );
  const body = await response.json();
  if (body.idToken) return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
  if (body.error && body.error.message === 'EMAIL_EXISTS') {
    return signInWithPassword(email, password);
  }
  throw new Error(`create user failed for ${email}: ${JSON.stringify(body)}`);
}

async function signInWithPassword(email, password) {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = await response.json();
  if (!body.idToken) throw new Error(`sign-in failed for ${email}: ${JSON.stringify(body)}`);
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function refreshIdToken(refreshToken) {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: refreshToken }).toString(),
  });
  const body = await response.json();
  return body.id_token;
}

// AP-3 wave 7 fix — replaces a prior `signUpAnonymously()` that called the
// Identity Toolkit anonymous sign-up REST endpoint, which mints a brand new
// random uid on every single call with no way to make it deterministic.
// Everything derived from that uid (`guestSessionId`, `subAccountId` below)
// was therefore a *different* document id on every script rerun, leaving
// the previous run's guest/sub-account documents orphaned in Firestore
// instead of being overwritten — the real root cause of the "Zeynep/Ayşe/
// Mehmet each appear twice" duplication observed in Wave 6. Every other
// identity/document in this script is already deterministic (RUN_ID-scoped
// ids with `.set()`, or the create-then-fall-back-to-existing pattern
// `createEmailPasswordUser` above uses for EMAIL_EXISTS) — this makes guest
// identities follow the same discipline via the Admin SDK, which (unlike
// the client sign-up endpoint) accepts a caller-supplied `uid`.
async function getOrCreateDeterministicGuestUser(uid) {
  try {
    await admin.auth().createUser({ uid });
  } catch (err) {
    if (err.code !== 'auth/uid-already-exists') throw err;
  }
  return { uid };
}

// A fixed run id (not time-based) — reruns target the SAME tenant/branch/
// staff/guest fixtures rather than accumulating a new set every time,
// which is what makes this safe to rerun idempotently.
const RUN_ID = 'ap3vis';
// The app's Flutter client hardcodes the single-tenant organization id as
// `'org-1'` (`kSingleTenantOrganizationId`, lib/core/config/
// current_organization.dart) — the same constant the backend's own
// `SINGLE_TENANT_ORGANIZATION_ID` (functions/src/completeCustomerProfile.ts)
// uses. Seeding under any other organization id (a prior `org-${RUN_ID}`
// here) produces real, correctly-synced staff claims that the client can
// never look up, since `_organizationId()` always resolves to `'org-1'` —
// confirmed root cause of "Giriş başarısız" despite a successful sign-in +
// claims sync. Restaurant/branch/product ids stay RUN_ID-scoped since
// nothing client-side hardcodes those; only the organization id must match.
const ORG_ID = 'org-1';
const RESTAURANT_ID = `restaurant-${RUN_ID}`;
const BRANCH_ID = `branch-${RUN_ID}`;
const PRODUCT_A = `product-${RUN_ID}-bowl`;
const PRODUCT_B = `product-${RUN_ID}-salata`;

const MANAGER_EMAIL = 'yonetici@abakus.test';
const CASHIER_EMAIL = 'kasiyer@abakus.test';
const OWNER_EMAIL = 'sahip@abakus.test';
const PASSWORD = 'GorselKabul2026!';

async function main() {
  console.log('Seeding tenant...');
  await db.collection('organizations').doc(ORG_ID).set({ name: 'Abaküs Görsel Kabul Testi', isActive: true });
  await db.collection('restaurants').doc(RESTAURANT_ID).set({ organizationId: ORG_ID, name: 'Abaküs Merkez', isActive: true });
  await db.collection('branches').doc(BRANCH_ID).set({
    restaurantId: RESTAURANT_ID, organizationId: ORG_ID, name: 'Merkez Şube', status: 'active', emergencyStopped: false,
  });
  await db.collection('entitlements').doc(`${ORG_ID}_organization_${ORG_ID}_pos`).set({
    organizationId: ORG_ID, scopeType: 'organization', scopeId: ORG_ID, module: 'pos', status: 'active', version: 1,
  });

  await db.collection('menuProducts').doc(PRODUCT_A).set({
    organizationId: ORG_ID, restaurantId: RESTAURANT_ID, categoryId: 'cat_standard', name: 'Klasik Bowl',
    basePriceMinorUnits: 12000, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
  });
  await db.collection('menuProducts').doc(PRODUCT_B).set({
    organizationId: ORG_ID, restaurantId: RESTAURANT_ID, categoryId: 'cat_standard', name: 'Yeşil Salata',
    basePriceMinorUnits: 9500, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
  });
  // AP-3 wave 7 — the customer-facing Menu screen and the POS staff-entry
  // dropdown both browse `AbakusMenuCatalog` (lib/features/menu/data/
  // abakus_menu_catalog.dart), a static Dart catalog entirely separate from
  // this collection — neither reads `menuProducts` for browsing. A real
  // customer order submitted through that real catalog references its real
  // ids (e.g. `prod_mexifit_bowl`), which `submitDineInOrder` then
  // correctly, securely rejects as "does not exist" if this collection
  // never heard of them — exactly the fail-closed behavior a stale/unknown
  // product id is supposed to get, confirmed directly while producing this
  // wave's real customer-order evidence. Seeding this one real catalog id
  // (matching the static catalog's own name/price exactly) is what makes a
  // real end-to-end customer QR order through the actual displayed menu
  // possible at all — PRODUCT_A/PRODUCT_B above remain the separate,
  // POS-fixture-only ids the pre-seeded orders/splits/staff-entry-dropdown
  // scenarios already depend on and keep using.
  await db.collection('menuProducts').doc('prod_mexifit_bowl').set({
    organizationId: ORG_ID, restaurantId: RESTAURANT_ID, categoryId: 'cat_bowl', name: 'Mexifit Bowl',
    basePriceMinorUnits: 43000, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
  });

  console.log('Creating staff accounts (email/password)...');
  const managerAuth = await createEmailPasswordUser(MANAGER_EMAIL, PASSWORD, 'Test Yönetici');
  const cashierAuth = await createEmailPasswordUser(CASHIER_EMAIL, PASSWORD, 'Test Kasiyer');

  console.log('Bootstrapping manager as first org admin (idempotent across reruns)...');
  await callCallable(fn('bootstrapFirstAdminAccount'), { organizationId: ORG_ID }, managerAuth.idToken).catch((err) => {
    if (!String(err.message).includes('already has at least one membership')) throw err;
  });
  await callCallable(fn('syncOwnStaffClaims'), {}, managerAuth.idToken);
  managerAuth.idToken = await refreshIdToken(managerAuth.refreshToken);

  console.log('Granting cashier the staff role + branch access...');
  await db.collection('memberships').doc(`${ORG_ID}_${cashierAuth.uid}`).set({
    organizationId: ORG_ID, uid: cashierAuth.uid, roles: ['staff'], branchAccess: [], restaurantAccess: [], status: 'active', version: 1,
  });
  await callCallable(fn('assignStaffRole'), { organizationId: ORG_ID, targetUid: cashierAuth.uid, role: 'staff' }, managerAuth.idToken);
  await callCallable(fn('grantStaffBranchAccess'), { organizationId: ORG_ID, targetUid: cashierAuth.uid, branchId: BRANCH_ID }, managerAuth.idToken);
  await callCallable(fn('grantStaffBranchAccess'), { organizationId: ORG_ID, targetUid: managerAuth.uid, branchId: BRANCH_ID }, managerAuth.idToken);
  await callCallable(fn('syncOwnStaffClaims'), {}, cashierAuth.idToken);
  cashierAuth.idToken = await refreshIdToken(cashierAuth.refreshToken);
  await callCallable(fn('syncOwnStaffClaims'), {}, managerAuth.idToken);
  managerAuth.idToken = await refreshIdToken(managerAuth.refreshToken);

  console.log('Seeding tables...');
  const availableTableId = `table-${RUN_ID}-1`;
  const occupiedTableId = `table-${RUN_ID}-2`;
  const tableSessionId = `tsess-${RUN_ID}`;
  await db.collection('restaurantTables').doc(availableTableId).set({
    organizationId: ORG_ID, restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, activeTableSessionId: null, isActive: true, status: 'available',
    displayName: 'Masa 1', branchDisplayName: 'Abaküs Merkez',
  });
  // AP-3 — a real, active `tableQrCodes` token for the available table, so
  // the customer QR deep-link entry route (`/table/:token`,
  // `TableGuestEntryScreen`) has a genuine `valid` preview to open against,
  // matching `resolveTableQrTokenInternal`'s exact schema
  // (functions/src/qrTokenResolution.ts).
  const availableTableQrToken = `qrtoken-${RUN_ID}-available`;
  await db.collection('tableQrCodes').doc(availableTableQrToken).set({
    opaqueToken: availableTableQrToken, tableId: availableTableId, status: 'active', expiresAt: null,
  });
  await db.collection('restaurantTables').doc(occupiedTableId).set({
    organizationId: ORG_ID, restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, activeTableSessionId: tableSessionId, isActive: true, status: 'occupied',
  });
  await db.collection('tableSessions').doc(tableSessionId).set({
    organizationId: ORG_ID, restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, tableId: occupiedTableId,
    status: 'active', openedAt: Timestamp.now(), closedAt: null, openedByType: 'guestQrScan', openedByStaffUid: null,
    transferredFromTableId: null, version: 1,
  });

  console.log('Seeding three guests with sub-accounts...');
  // Migration guard for an emulator that still holds orphaned documents
  // from a pre-fix run of this script (random-uid-derived ids that no
  // longer match the deterministic ones below) — deletes only documents
  // scoped to this exact deterministic `tableSessionId`, never anything
  // else. A fresh emulator has nothing to delete here; this only matters
  // for a long-lived emulator that was seeded by an older version.
  const expectedGuestUids = new Set([`guest-${RUN_ID}-ayse`, `guest-${RUN_ID}-mehmet`, `guest-${RUN_ID}-zeynep`]);
  for (const collectionName of ['guestSubAccounts', 'tableGuestSessions']) {
    const stale = await db.collection(collectionName).where('tableSessionId', '==', tableSessionId).get();
    for (const doc of stale.docs) {
      const ownerUid = doc.data().ownerAuthUid || doc.data().guestAuthUid;
      if (!expectedGuestUids.has(ownerUid)) await doc.ref.delete();
    }
  }
  const guest1 = await getOrCreateDeterministicGuestUser(`guest-${RUN_ID}-ayse`); // Ayşe
  const guest2 = await getOrCreateDeterministicGuestUser(`guest-${RUN_ID}-mehmet`); // Mehmet
  const guest3 = await getOrCreateDeterministicGuestUser(`guest-${RUN_ID}-zeynep`); // Zeynep

  async function seedGuest(guest, displayName) {
    const guestSessionId = `tgs-${RUN_ID}-${guest.uid}`;
    await db.collection('tableGuestSessions').doc(guestSessionId).set({
      organizationId: ORG_ID, restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, tableId: occupiedTableId, tableSessionId,
      guestAuthUid: guest.uid, status: 'active', createdAt: Timestamp.now(),
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 6 * 60 * 60 * 1000)),
      lastActivityAt: Timestamp.now(), qrTokenId: `qrtoken-${RUN_ID}`, reservationContextId: null,
    });
    const subAccountId = `subaccount-${tableSessionId}-${guest.uid}`;
    await db.collection('guestSubAccounts').doc(subAccountId).set({
      organizationId: ORG_ID, branchId: BRANCH_ID, tableSessionId,
      ownerType: 'guestSession', ownerSessionRef: `tableGuestSessions/${guestSessionId}`, ownerAuthUid: guest.uid,
      displayName, status: 'open', createdAt: Timestamp.now(), createdByStaffUid: null, version: 1,
    });
    return { guestSessionId, subAccountId };
  }
  const g1 = await seedGuest(guest1, 'Ayşe');
  const g2 = await seedGuest(guest2, 'Mehmet');
  const g3 = await seedGuest(guest3, 'Zeynep');

  console.log('Seeding orders (pending / accepted / rejected / proposedChange lines)...');
  function moneyField(minorUnits) { return { minorUnits, currencyCode: 'TRY' }; }
  function baseOrderFields(orderId, subAccountId, guestAuthUid, mode) {
    return {
      organizationId: ORG_ID, orderId, orderNumber: orderId, status: 'pendingConfirmation', channel: 'dineInQr',
      branchId: BRANCH_ID, restaurantId: RESTAURANT_ID, customerId: null, tableId: occupiedTableId,
      tableSessionId: mode === 'staffEntry' ? null : g1.guestSessionId,
      dineInSessionGroupId: tableSessionId, guestSessionId: null, guestAuthUid, reservationContextId: null,
      takeawayEntrySessionId: null, pickupMode: null, pickupTime: null, pickupTimeTimestamp: null,
      contactFirstName: null, contactLastName: null, subAccountId, mode, createdAt: Timestamp.now(), version: 1,
    };
  }

  const order1Id = `order-${RUN_ID}-1`;
  await db.collection('orders').doc(order1Id).set({
    ...baseOrderFields(order1Id, g1.subAccountId, guest1.uid, 'guestSession'),
    linesDispositionSummary: 'pending',
    lines: [
      { productId: PRODUCT_A, productName: 'Klasik Bowl', quantity: 1, unitPrice: moneyField(12000), unitPriceMinorUnits: 12000, modifierTotalMinorUnits: 0, status: 'pendingApproval', subAccountId: g1.subAccountId, selectedModifiers: [], note: '' },
      { productId: PRODUCT_B, productName: 'Yeşil Salata', quantity: 1, unitPrice: moneyField(9500), unitPriceMinorUnits: 9500, modifierTotalMinorUnits: 0, status: 'accepted', subAccountId: g1.subAccountId, selectedModifiers: [], note: '' },
    ],
  });

  const order2Id = `order-${RUN_ID}-2`;
  await db.collection('orders').doc(order2Id).set({
    ...baseOrderFields(order2Id, g2.subAccountId, guest2.uid, 'guestSession'),
    linesDispositionSummary: 'pending',
    lines: [
      {
        productId: PRODUCT_A, productName: 'Klasik Bowl', quantity: 1, unitPrice: moneyField(12000), unitPriceMinorUnits: 12000,
        modifierTotalMinorUnits: 0, status: 'proposedChange', subAccountId: g2.subAccountId, selectedModifiers: [], note: '',
        proposedChange: {
          proposedProductId: PRODUCT_B, proposedProductName: 'Yeşil Salata', proposedQuantity: 1,
          reasonCode: 'outOfStock', reasonMessage: 'Seçtiğiniz ürün tükendi, bu ürünü öneriyoruz.',
          proposedByStaffUid: cashierAuth.uid, proposedAt: Timestamp.now().toDate().toISOString(),
        },
      },
    ],
  });

  const order3Id = `order-${RUN_ID}-3`;
  await db.collection('orders').doc(order3Id).set({
    ...baseOrderFields(order3Id, g3.subAccountId, guest3.uid, 'guestSession'),
    linesDispositionSummary: 'resolved',
    lines: [
      { productId: PRODUCT_B, productName: 'Yeşil Salata', quantity: 2, unitPrice: moneyField(9500), unitPriceMinorUnits: 9500, modifierTotalMinorUnits: 0, status: 'rejected', subAccountId: g3.subAccountId, selectedModifiers: [], note: '' },
    ],
  });

  const staffOrderId = `order-${RUN_ID}-staff`;
  await db.collection('orders').doc(staffOrderId).set({
    ...baseOrderFields(staffOrderId, g1.subAccountId, guest1.uid, 'staffEntry'),
    linesDispositionSummary: 'resolved',
    lines: [
      { productId: PRODUCT_A, productName: 'Klasik Bowl', quantity: 1, unitPrice: moneyField(12000), unitPriceMinorUnits: 12000, modifierTotalMinorUnits: 0, status: 'accepted', subAccountId: g1.subAccountId, selectedModifiers: [], note: '' },
    ],
  });

  console.log('Opening a check and splitting the staff-entered line by product...');
  const checkId = `check-${RUN_ID}`;
  await db.collection('checks').doc(checkId).set({
    organizationId: ORG_ID, branchId: BRANCH_ID, tableSessionId, status: 'open', paymentActivityStarted: false,
    computedTotalMinorUnits: 12000, currencyCode: 'TRY', openedAt: Timestamp.now(), readyForPaymentAt: null,
    cancelledAt: null, createdByStaffUid: cashierAuth.uid, version: 1,
  });
  const allocationId = `alloc-${RUN_ID}-1`;
  await db.collection('checkAllocations').doc(allocationId).set({
    checkId, organizationId: ORG_ID, branchId: BRANCH_ID, tableSessionId, subAccountId: g1.subAccountId,
    splitMethod: 'product', sourceComposition: [{ sourceOrderId: staffOrderId, sourceLineIndex: 0, quantity: 1, amountMinorUnits: 12000 }],
    allocatedAmountMinorUnits: 12000, currencyCode: 'TRY', status: 'active', note: null,
    createdAt: Timestamp.now(), createdByStaffUid: cashierAuth.uid, version: 1,
  });

  console.log('Seeding a pending remote approval (financial-adjustment request)...');
  const adjustmentId = `adjustment-${RUN_ID}-1`;
  const approvalRequestId = `approval-checkFinancialAdjustment-checkFinancialAdjustments_${adjustmentId}-v1`;
  await db.collection('checkFinancialAdjustments').doc(adjustmentId).set({
    checkId, organizationId: ORG_ID, branchId: BRANCH_ID, scope: 'check', scopeRef: { allocationId: null, subAccountId: null },
    adjustmentType: 'percentage', percentageBasisPoints: 1000, fixedAmountMinorUnits: null,
    requestedAppliedAmountMinorUnits: 1200, appliedAmountMinorUnits: null, currencyCode: 'TRY',
    reasonCode: 'customerSatisfaction', reasonMessage: 'Müşteri memnuniyeti için %10 indirim talebi.',
    approvalRequestRef: approvalRequestId, requestedByStaffUid: cashierAuth.uid, status: 'pendingApproval',
    reversalOf: null, calculationSnapshot: { baseAmountMinorUnits: 12000, policyVersion: 'AP3-W2C-v1' },
    createdAt: Timestamp.now(), version: 1,
  });
  await db.collection('remoteApprovalRequests').doc(approvalRequestId).set({
    requestId: approvalRequestId, organizationId: ORG_ID, branchId: BRANCH_ID, actionType: 'checkFinancialAdjustment',
    requestedByActorUid: cashierAuth.uid, targetAggregateRef: `checkFinancialAdjustments/${adjustmentId}`, targetAggregateVersion: 1,
    payloadHash: 'percentage-1200', status: 'pending', respondedByActorUid: null, respondedAt: null, escalatedTo: null,
    createdAt: Timestamp.now(), expiresAt: Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000), version: 1,
  });

  console.log('Seeding tenant + platform customer directory entries...');
  const directoryCustomers = [
    { uid: `cust-${RUN_ID}-1`, name: 'Ahmet Yılmaz' },
    { uid: `cust-${RUN_ID}-2`, name: 'Elif Kaya' },
    { uid: `cust-${RUN_ID}-3`, name: 'Can Demir' },
  ];
  for (const c of directoryCustomers) {
    await db.collection('customerDirectoryEntries').doc(`${ORG_ID}_${c.uid}`).set({
      organizationId: ORG_ID, customerId: c.uid, displayName: c.name, displayNameNormalized: c.name.toLocaleLowerCase('tr'),
      phoneNumber: '+905551234567', phoneSearchHash: 'synthetic-fixture-hash', registrationDate: Timestamp.now(),
      lastActivityAt: Timestamp.now(), accountState: 'active', relatedBranchIds: [BRANCH_ID], lastOrderAt: Timestamp.now(),
      totalOrderCount: 3, updatedAt: Timestamp.now(), version: 1,
    });
    await db.collection('platformCustomerDirectoryEntries').doc(c.uid).set({
      uid: c.uid, displayName: c.name, displayNameNormalized: c.name.toLocaleLowerCase('tr'),
      phoneNumber: '+905551234567', phoneSearchHash: 'synthetic-fixture-hash', registrationDate: Timestamp.now(),
      accountState: 'active', updatedAt: Timestamp.now(), version: 1,
    });
  }

  console.log('Creating a Platform Owner account...');
  const ownerAuth = await createEmailPasswordUser(OWNER_EMAIL, PASSWORD, 'Test Platform Sahibi');
  await db.collection('platformMembers').doc(ownerAuth.uid).set({
    uid: ownerAuth.uid, roles: ['platformOwner'], status: 'active', createdAt: Timestamp.now(), version: 1,
  });

  // Local full-access review user — grants the SAME uid that already holds
  // real tenant `admin` (the maximal tenant role: identical permission set
  // to `tenantOwner` in DEFAULT_STAFF_ROLE_PERMISSIONS, staffAuthorization
  // .ts) real Platform Owner membership too, via the exact same direct-write
  // pattern already used for `ownerAuth.uid` two lines above — never a
  // parallel/simulated auth system. `.set()` on a fixed doc id
  // (`platformMembers/{managerAuth.uid}`) is naturally idempotent: rerunning
  // produces the byte-identical document, never a duplicate. The real
  // Flutter app's own Platform sign-in flow calls `syncOwnPlatformClaims`
  // itself on sign-in (mirroring `FirebaseStaffAuthRepository.signIn()`'s
  // own `syncOwnStaffClaims` call) — this script only needs to write the
  // Firestore membership record, exactly as it already does for
  // `ownerAuth.uid`, never the custom claim directly.
  console.log('Granting the local review account (manager/admin uid) Platform Owner membership too...');
  await db.collection('platformMembers').doc(managerAuth.uid).set({
    uid: managerAuth.uid, roles: ['platformOwner'], status: 'active', createdAt: Timestamp.now(), version: 1,
  });

  console.log('\nDONE. Local login instructions:\n');
  console.log('  Staff/Admin sign-in  (route /admin -> "Giriş Yap"):');
  console.log(`    E-posta : ${CASHIER_EMAIL}`);
  console.log(`    Şifre   : ${PASSWORD}`);
  console.log('  Manager (approvals, branch management):');
  console.log(`    E-posta : ${MANAGER_EMAIL}`);
  console.log(`    Şifre   : ${PASSWORD}`);
  console.log('  Platform Owner sign-in  (route /platform):');
  console.log(`    E-posta : ${OWNER_EMAIL}`);
  console.log(`    Şifre   : ${PASSWORD}`);
  console.log('  Local full-access review account (tenant admin + Platform Owner, SAME uid):');
  console.log(`    E-posta : ${MANAGER_EMAIL}`);
  console.log(`    Şifre   : ${PASSWORD}`);
  console.log(`\n  Organization: ${ORG_ID}   Branch: ${BRANCH_ID}`);
  console.log(`  Occupied table (live demo data): ${occupiedTableId}`);
  console.log(`  Available table: ${availableTableId}`);
}

module.exports = { main };

if (require.main === module) {
  main().then(() => process.exit(0)).catch((err) => { console.error(err); process.exit(1); });
}
