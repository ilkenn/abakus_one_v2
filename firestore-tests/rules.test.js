// Emulator-backed Firestore Security Rules tests — Phase 9
// (docs/decisions.md ADR-026). Runs entirely against the local Firestore
// Emulator via `firebase emulators:exec` — no real Firebase project
// credentials are used or required. See docs/firestore_data_model.md for
// the collection strategy and requirement -> rule mechanism this suite
// verifies.
//
// Run with: cd firestore-tests && npm install && npm run test:emulator
// (see package.json's test:emulator script, which wraps this file with
// `firebase emulators:exec` from the repo root so firestore.rules
// resolves correctly).

import { test, before, after } from 'node:test';
import assert from 'node:assert';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import {
  setDoc,
  doc,
  getDoc,
  updateDoc,
  deleteDoc,
  Timestamp,
  collection,
  query,
  where,
  getDocs,
} from 'firebase/firestore';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'abakus-one-rules-test',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

async function seed(setupFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setupFn(context.firestore());
  });
}

test('a tenant member can read their own organization', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'organizations/org-1'), { name: 'Abaküs' });
  });
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(getDoc(doc(alice, 'organizations/org-1')));
});

test('cross-tenant read is denied — a member of org-2 cannot read org-1', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'organizations/org-1'), { name: 'Abaküs' });
  });
  const eve = testEnv
    .authenticatedContext('eve', { organizationAccess: ['org-2'] })
    .firestore();

  await assertFails(getDoc(doc(eve, 'organizations/org-1')));
});

test('an unauthenticated request is denied', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'organizations/org-1'), { name: 'Abaküs' });
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'organizations/org-1')));
});

test('a client cannot assign themselves an organization — direct write to organizations is always denied, even for a member', async () => {
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(alice, 'organizations/org-1'), { name: 'Hijacked' }),
  );
});

test('a client cannot promote their own role via memberships', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'memberships/org-1_alice'), {
      organizationId: 'org-1',
      roles: ['staff'],
    });
  });
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    updateDoc(doc(alice, 'memberships/org-1_alice'), { roles: ['admin'] }),
  );
});

test('a client can read only their own membership document, never another user\'s', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'memberships/org-1_alice'), {
      organizationId: 'org-1',
      roles: ['staff'],
    });
    await setDoc(doc(db, 'memberships/org-1_bob'), {
      organizationId: 'org-1',
      roles: ['admin'],
    });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertSucceeds(getDoc(doc(alice, 'memberships/org-1_alice')));
  await assertFails(getDoc(doc(alice, 'memberships/org-1_bob')));
});

test('a client cannot write an arbitrary entitlement grant', async () => {
  const alice = testEnv
    .authenticatedContext('alice', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['tenantOwner'] },
    })
    .firestore();

  await assertFails(
    setDoc(doc(alice, 'entitlements/free-forever'), {
      organizationId: 'org-1',
      module: 'ai',
      status: 'active',
    }),
  );
});

test('a tenant member can read an entitlement grant for their own organization', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'entitlements/g1'), {
      organizationId: 'org-1',
      module: 'inventory',
      status: 'active',
    });
  });
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(getDoc(doc(alice, 'entitlements/g1')));
});

test('a branch denormalizes organizationId, read-scoped to org members only', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'branches/branch-1'), {
      restaurantId: 'restaurant-1',
      organizationId: 'org-1',
      name: 'Merkez Şube',
    });
  });
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();
  const eve = testEnv
    .authenticatedContext('eve', { organizationAccess: ['org-2'] })
    .firestore();

  await assertSucceeds(getDoc(doc(alice, 'branches/branch-1')));
  await assertFails(getDoc(doc(eve, 'branches/branch-1')));
});

test('an order can be created by an org member in the created status', async () => {
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(
    setDoc(doc(alice, 'orders/order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      status: 'created',
    }),
  );
});

test('an order can be created by an org member directly in the pendingConfirmation status — matches the real client, which applies the created -> pendingConfirmation transition in-memory before the first write (Phase 9 adversarial review fix)', async () => {
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(
    setDoc(doc(alice, 'orders/order-2'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      status: 'pendingConfirmation',
    }),
  );
});

test('an order cannot be created directly into a non-created status — status transitions are server-authoritative', async () => {
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(alice, 'orders/order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      status: 'completed',
    }),
  );
});

test('a client cannot transition an existing order\'s status directly (client update is always denied)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      status: 'created',
    });
  });
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    updateDoc(doc(alice, 'orders/order-1'), { status: 'completed' }),
  );
});

test('a customer can read their own order (Phase 9K, docs/decisions.md ADR-026) — required for CanonicalOrderRepository.findByCustomerId, the customer-facing Orders/Order-Detail read path', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/order-3'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      status: 'pendingConfirmation',
      customerId: 'customer-alice',
    });
  });
  const alice = testEnv.authenticatedContext('customer-alice').firestore();

  await assertSucceeds(getDoc(doc(alice, 'orders/order-3')));
});

test('a customer cannot read another customer\'s order — IDOR protection, verified adversarially for the Phase 9K read-path migration', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/order-4'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      status: 'pendingConfirmation',
      customerId: 'customer-victim',
    });
  });
  const eve = testEnv.authenticatedContext('customer-attacker').firestore();

  await assertFails(getDoc(doc(eve, 'orders/order-4')));
});

test('an unauthenticated request cannot read a customer order by customerId', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/order-5'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      status: 'pendingConfirmation',
      customerId: 'customer-alice',
    });
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'orders/order-5')));
});

test('an org member (staff) with matching branch access can still read a customer order that is not their own customerId — staff read is unaffected by the customer-scoped rule addition', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/order-6'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      status: 'pendingConfirmation',
      customerId: 'customer-someone-else',
    });
  });
  const staffMember = testEnv
    .authenticatedContext('staff-bob', {
      organizationAccess: ['org-1'],
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();

  await assertSucceeds(getDoc(doc(staffMember, 'orders/order-6')));
});

// -------------------------------------------------------------------------
// Faz R.3C.1 (initial audit) / R.3C.2 (hardening) — KDS/Orders branch
// authorization boundary.
//
// `FirestoreKitchenTicketRepository`'s client-side `branchId` query filter
// is NOT itself an authorization boundary — it only decides which orders a
// given screen instance asks for. Faz R.3C.1 found and documented that
// organization membership ALONE was the only real boundary at the time
// (any org member could read every branch's orders) — judged unacceptable
// for the multi-branch SaaS architecture on its own audit. Faz R.3C.2
// closes it: the real boundary is now `isOrgMember(...) &&
// hasBranchAccess(organizationId, branchId)`, sourced from the
// `branchAccess` custom claim (`resyncClaimsForUid`,
// `functions/src/staffMembership.ts`), never a client-supplied value. The
// tests below prove the new boundary directly — items 1-7 of Faz R.3C.2's
// own required 15-scenario list.
// -------------------------------------------------------------------------

test('Orders branch authorization 1: Branch A staff (with Branch A access) can read a Branch A order', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/branch-a-order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-a',
      status: 'confirmed',
      customerId: 'customer-someone',
    });
  });
  const staffA = testEnv
    .authenticatedContext('staff-branch-a', {
      organizationAccess: ['org-1'],
      branchAccess: { 'org-1': ['branch-a'] },
    })
    .firestore();

  await assertSucceeds(getDoc(doc(staffA, 'orders/branch-a-order-1')));
});

test('Orders branch authorization 2: Branch-A-only staff cannot read a Branch B order in the same organization', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/branch-b-order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-b',
      status: 'confirmed',
      customerId: 'customer-someone',
    });
  });
  const staffA = testEnv
    .authenticatedContext('staff-branch-a-only', {
      organizationAccess: ['org-1'],
      branchAccess: { 'org-1': ['branch-a'] },
    })
    .firestore();

  await assertFails(getDoc(doc(staffA, 'orders/branch-b-order-1')));
});

test('Orders branch authorization 3: staff granted both Branch A and Branch B access can read both', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/multi-branch-order-a'), {
      organizationId: 'org-1',
      branchId: 'branch-a',
      status: 'confirmed',
      customerId: 'customer-someone',
    });
    await setDoc(doc(db, 'orders/multi-branch-order-b'), {
      organizationId: 'org-1',
      branchId: 'branch-b',
      status: 'confirmed',
      customerId: 'customer-someone',
    });
  });
  const multiBranchStaff = testEnv
    .authenticatedContext('staff-multi-branch', {
      organizationAccess: ['org-1'],
      branchAccess: { 'org-1': ['branch-a', 'branch-b'] },
    })
    .firestore();

  await assertSucceeds(getDoc(doc(multiBranchStaff, 'orders/multi-branch-order-a')));
  await assertSucceeds(getDoc(doc(multiBranchStaff, 'orders/multi-branch-order-b')));
});

test('Orders branch authorization 4: a member of a different organization is denied, even with a matching branchId claimed elsewhere', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/kds-order-org1'), {
      organizationId: 'org-1',
      branchId: 'branch-a',
      status: 'confirmed',
      customerId: 'customer-someone',
    });
  });
  const outsider = testEnv
    .authenticatedContext('staff-outsider', {
      organizationAccess: ['org-2'],
      branchAccess: { 'org-2': ['branch-a'] },
    })
    .firestore();

  await assertFails(getDoc(doc(outsider, 'orders/kds-order-org1')));
});

test('Orders branch authorization 5: an arbitrary/spoofed client-supplied branchId cannot expand authority — the rule checks the document\'s own branchId, never a query parameter', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/kds-order-org1-b'), {
      organizationId: 'org-1',
      branchId: 'branch-y',
      status: 'confirmed',
      customerId: 'customer-someone',
    });
  });
  // A staff member with access to a DIFFERENT branch cannot read this
  // document no matter what branchId their own client-side query happens
  // to be scoped to — the rule checks the DOCUMENT's own branchId, never
  // anything the query filter claimed.
  const wrongBranchStaff = testEnv
    .authenticatedContext('staff-wrong-branch', {
      organizationAccess: ['org-1'],
      branchAccess: { 'org-1': ['branch-z'] },
    })
    .firestore();
  await assertFails(getDoc(doc(wrongBranchStaff, 'orders/kds-order-org1-b')));

  // The legitimate branch-y-authorized member, by contrast, succeeds.
  const legitimateMember = testEnv
    .authenticatedContext('staff-legit', {
      organizationAccess: ['org-1'],
      branchAccess: { 'org-1': ['branch-y'] },
    })
    .firestore();
  await assertSucceeds(getDoc(doc(legitimateMember, 'orders/kds-order-org1-b')));
});

test('Orders branch authorization 6: a missing branchAccess claim entirely fails closed (zero branch access, not "every branch")', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/no-branch-claim-order'), {
      organizationId: 'org-1',
      branchId: 'branch-a',
      status: 'confirmed',
      customerId: 'customer-someone',
    });
  });
  // Org member, real roles, but no branchAccess claim key at all — e.g. a
  // token minted before this phase, or a membership with an empty grant.
  const noClaimStaff = testEnv
    .authenticatedContext('staff-no-branch-claim', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['manager'] },
    })
    .firestore();

  await assertFails(getDoc(doc(noClaimStaff, 'orders/no-branch-claim-order')));
});

test('Orders branch authorization 7: a malformed branchAccess claim (wrong shape) fails closed', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/malformed-branch-claim-order'), {
      organizationId: 'org-1',
      branchId: 'branch-a',
      status: 'confirmed',
      customerId: 'customer-someone',
    });
  });
  // branchAccess present but the wrong shape (a bare string, not a map of
  // organizationId -> branchId list) — must deny, not throw a rule-
  // evaluation error that somehow resolves to allow.
  const malformedClaimStaff = testEnv
    .authenticatedContext('staff-malformed-branch-claim', {
      organizationAccess: ['org-1'],
      branchAccess: 'branch-a',
    })
    .firestore();

  await assertFails(getDoc(doc(malformedClaimStaff, 'orders/malformed-branch-claim-order')));
});

test('audit events are read-only for members, never client-writable (append-only, server-only)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'auditEvents/evt-1'), {
      organizationId: 'org-1',
      type: 'orderCreated',
    });
  });
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(getDoc(doc(alice, 'auditEvents/evt-1')));
  await assertFails(
    setDoc(doc(alice, 'auditEvents/evt-2'), {
      organizationId: 'org-1',
      type: 'fabricated',
    }),
  );
  await assertFails(
    updateDoc(doc(alice, 'auditEvents/evt-1'), { type: 'tampered' }),
  );
});

// ---------------------------------------------------------------------
// Table Guest Session (QR table ordering, Phase 1) — a session is
// created exclusively by the `openTableGuestSession` Cloud Function
// (Admin SDK, bypasses these rules entirely); these tests only cover
// what a *client* may do against an already-seeded session document.
// `orders` create/read are not yet extended to consult this collection
// (Phase 3) — no test here touches `orders`.
// ---------------------------------------------------------------------

test('a table guest can read their own session (owner match on guestAuthUid)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableGuestSessions/session-1'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      guestAuthUid: 'guest-uid-1',
      status: 'active',
    });
  });
  const guest = testEnv.authenticatedContext('guest-uid-1').firestore();

  await assertSucceeds(getDoc(doc(guest, 'tableGuestSessions/session-1')));
});

test('another authenticated uid cannot read someone else\'s table guest session — IDOR/cross-guest protection', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableGuestSessions/session-2'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      guestAuthUid: 'guest-uid-2',
      status: 'active',
    });
  });
  const attacker = testEnv.authenticatedContext('guest-uid-attacker').firestore();

  await assertFails(getDoc(doc(attacker, 'tableGuestSessions/session-2')));
});

test('an org member (staff) cannot read a table guest session either — no staff exemption exists for this collection', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableGuestSessions/session-3'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      guestAuthUid: 'guest-uid-3',
      status: 'active',
    });
  });
  const staffMember = testEnv
    .authenticatedContext('staff-bob', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(getDoc(doc(staffMember, 'tableGuestSessions/session-3')));
});

test('an unauthenticated request cannot read a table guest session', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableGuestSessions/session-4'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      guestAuthUid: 'guest-uid-4',
      status: 'active',
    });
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'tableGuestSessions/session-4')));
});

test('a client can never directly create a table guest session — Cloud Function (Admin SDK) only', async () => {
  const guest = testEnv.authenticatedContext('guest-uid-5').firestore();

  await assertFails(
    setDoc(doc(guest, 'tableGuestSessions/session-5'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      guestAuthUid: 'guest-uid-5',
      status: 'active',
    }),
  );
});

test('a client can never directly update their own table guest session — e.g. extending expiresAt or re-pointing tableId', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableGuestSessions/session-6'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      guestAuthUid: 'guest-uid-6',
      status: 'active',
    });
  });
  const guest = testEnv.authenticatedContext('guest-uid-6').firestore();

  await assertFails(
    updateDoc(doc(guest, 'tableGuestSessions/session-6'), {
      tableId: 'table-999',
    }),
  );
});

test('tableQrCodes and restaurantTables are unreadable by any client — covered by the fail-closed default, never a direct client lookup', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableQrCodes/qr-1'), {
      tableId: 'table-1',
      opaqueToken: 'some-opaque-token',
      status: 'active',
    });
    await setDoc(doc(db, 'restaurantTables/table-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      status: 'available',
      isActive: true,
    });
  });
  const staffMember = testEnv
    .authenticatedContext('staff-bob', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(getDoc(doc(staffMember, 'tableQrCodes/qr-1')));
  await assertFails(getDoc(doc(staffMember, 'restaurantTables/table-1')));
});

// ---------------------------------------------------------------------
// Table Guest Session order authorization (Phase 3) — the actual fix for
// the reported `orders/local-order-X PERMISSION_DENIED` bug. The
// `isOrgMember` staff branch is never touched by any test in this
// section; the pre-existing "an order can be created by an org member..."
// tests above already prove that branch still passes unchanged.
// ---------------------------------------------------------------------

function activeGuestSession(overrides = {}) {
  return {
    organizationId: 'org-1',
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    tableId: 'table-1',
    guestAuthUid: 'guest-uid-default',
    status: 'active',
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 60 * 60 * 1000)),
    ...overrides,
  };
}

function tableOrderPayload(overrides = {}) {
  return {
    organizationId: 'org-1',
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    tableId: 'table-1',
    tableSessionId: 'tgs-default',
    customerId: null,
    guestAuthUid: 'guest-uid-default',
    channel: 'dineInQr',
    status: 'pendingConfirmation',
    ...overrides,
  };
}

// Phase 3.1: simulates a real, phone-verified customer's Firebase Auth ID
// token via rules-unit-testing's tokenOptions. Empirically confirmed
// against the real local Auth Emulator (this phase's own report — decoded
// the actual ID token JWTs) that `signInAnonymously()` produces exactly
// `firebase.sign_in_provider: 'anonymous'` and a real phone sign-in
// produces exactly `firebase.sign_in_provider: 'phone'` — this simulates
// that same real token shape for rules testing, matching this file's own
// established convention of simulating claims via `authenticatedContext`
// (e.g. `organizationAccess` for staff) rather than performing a real
// sign-in per test.
function customerContext(uid) {
  return testEnv
    .authenticatedContext(uid, { firebase: { sign_in_provider: 'phone' } })
    .firestore();
}

// ===== Variant A: anonymous Table Guest =====

test('anonymous + valid table session + customerId null + correct guestAuthUid -> allow (direct regression test for the reported PERMISSION_DENIED bug)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-1'),
      activeGuestSession({ guestAuthUid: 'guest-uid-1' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-1').firestore();

  await assertSucceeds(
    setDoc(
      doc(guest, 'orders/guest-order-1'),
      tableOrderPayload({ tableSessionId: 'tgs-1', guestAuthUid: 'guest-uid-1' }),
    ),
  );
});

test('an unauthenticated request cannot create an order via the table guest session path', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-2'),
      activeGuestSession({ guestAuthUid: 'guest-uid-2' }),
    );
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(
    setDoc(
      doc(anon, 'orders/guest-order-2'),
      tableOrderPayload({ tableSessionId: 'tgs-2', guestAuthUid: 'guest-uid-2' }),
    ),
  );
});

test('wrong session owner: a different authenticated uid cannot create an order using someone else\'s table guest session', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-3'),
      activeGuestSession({ guestAuthUid: 'guest-uid-3' }),
    );
  });
  const attacker = testEnv.authenticatedContext('guest-uid-attacker').firestore();

  await assertFails(
    setDoc(
      doc(attacker, 'orders/guest-order-3'),
      tableOrderPayload({ tableSessionId: 'tgs-3', guestAuthUid: 'guest-uid-attacker' }),
    ),
  );
});

test('anonymous + wrong guestAuthUid on the order payload itself -> deny (owns a valid session, but claims a different guestAuthUid)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-3b'),
      activeGuestSession({ guestAuthUid: 'guest-uid-3b' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-3b').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-3b'),
      tableOrderPayload({ tableSessionId: 'tgs-3b', guestAuthUid: 'someone-else' }),
    ),
  );
});

test('expired session create -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-4'),
      activeGuestSession({
        guestAuthUid: 'guest-uid-4',
        expiresAt: Timestamp.fromDate(new Date(Date.now() - 60 * 1000)),
      }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-4').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-4'),
      tableOrderPayload({ tableSessionId: 'tgs-4', guestAuthUid: 'guest-uid-4' }),
    ),
  );
});

test('revoked session create -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-5'),
      activeGuestSession({ guestAuthUid: 'guest-uid-5', status: 'revoked' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-5').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-5'),
      tableOrderPayload({ tableSessionId: 'tgs-5', guestAuthUid: 'guest-uid-5' }),
    ),
  );
});

test('cross organization -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-6'),
      activeGuestSession({ guestAuthUid: 'guest-uid-6' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-6').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-6'),
      tableOrderPayload({
        tableSessionId: 'tgs-6',
        guestAuthUid: 'guest-uid-6',
        organizationId: 'org-DIFFERENT',
      }),
    ),
  );
});

test('cross restaurant -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-7'),
      activeGuestSession({ guestAuthUid: 'guest-uid-7' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-7').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-7'),
      tableOrderPayload({
        tableSessionId: 'tgs-7',
        guestAuthUid: 'guest-uid-7',
        restaurantId: 'restaurant-DIFFERENT',
      }),
    ),
  );
});

test('cross branch -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-8'),
      activeGuestSession({ guestAuthUid: 'guest-uid-8' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-8').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-8'),
      tableOrderPayload({
        tableSessionId: 'tgs-8',
        guestAuthUid: 'guest-uid-8',
        branchId: 'branch-DIFFERENT',
      }),
    ),
  );
});

test('cross table -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-9'),
      activeGuestSession({ guestAuthUid: 'guest-uid-9' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-9').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-9'),
      tableOrderPayload({
        tableSessionId: 'tgs-9',
        guestAuthUid: 'guest-uid-9',
        tableId: 'table-DIFFERENT',
      }),
    ),
  );
});

test('an order referencing a nonexistent table guest session is denied (wrong/unknown tableSessionId)', async () => {
  const guest = testEnv.authenticatedContext('guest-uid-10').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-10'),
      tableOrderPayload({
        tableSessionId: 'tgs-does-not-exist',
        guestAuthUid: 'guest-uid-10',
      }),
    ),
  );
});

test('anonymous + customerId = own uid -> deny (a guest cannot spoof a customer identity by writing their own uid as customerId)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-11'),
      activeGuestSession({ guestAuthUid: 'guest-uid-11' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-11').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-11'),
      tableOrderPayload({
        tableSessionId: 'tgs-11',
        guestAuthUid: 'guest-uid-11',
        customerId: 'guest-uid-11',
      }),
    ),
  );
});

test('wrong channel -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-12'),
      activeGuestSession({ guestAuthUid: 'guest-uid-12' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-12').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-12'),
      tableOrderPayload({
        tableSessionId: 'tgs-12',
        guestAuthUid: 'guest-uid-12',
        channel: 'delivery',
      }),
    ),
  );
});

test('invalid initial status -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-13'),
      activeGuestSession({ guestAuthUid: 'guest-uid-13' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-13').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-13'),
      tableOrderPayload({
        tableSessionId: 'tgs-13',
        guestAuthUid: 'guest-uid-13',
        status: 'completed',
      }),
    ),
  );
});

test('guest update -> deny (status transitions stay server-authoritative)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-14'),
      activeGuestSession({ guestAuthUid: 'guest-uid-14' }),
    );
    await setDoc(
      doc(db, 'orders/guest-order-14'),
      tableOrderPayload({ tableSessionId: 'tgs-14', guestAuthUid: 'guest-uid-14' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-14').firestore();

  await assertFails(
    updateDoc(doc(guest, 'orders/guest-order-14'), { status: 'confirmed' }),
  );
});

// ===== Variant B: authenticated (real, phone-verified) customer at a table =====

test('real customer + valid session + customerId own uid -> allow', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-20'),
      activeGuestSession({ guestAuthUid: 'customer-uid-1' }),
    );
  });
  const customer = customerContext('customer-uid-1');

  await assertSucceeds(
    setDoc(
      doc(customer, 'orders/customer-order-1'),
      tableOrderPayload({
        tableSessionId: 'tgs-20',
        guestAuthUid: 'customer-uid-1',
        customerId: 'customer-uid-1',
      }),
    ),
  );
});

test('real customer + wrong customerId -> deny (cannot attribute the order to a different uid than their own)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-21'),
      activeGuestSession({ guestAuthUid: 'customer-uid-2' }),
    );
  });
  const customer = customerContext('customer-uid-2');

  await assertFails(
    setDoc(
      doc(customer, 'orders/customer-order-2'),
      tableOrderPayload({
        tableSessionId: 'tgs-21',
        guestAuthUid: 'customer-uid-2',
        customerId: 'someone-else-uid',
      }),
    ),
  );
});

test('real customer + wrong guestAuthUid -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-22'),
      activeGuestSession({ guestAuthUid: 'customer-uid-3' }),
    );
  });
  const customer = customerContext('customer-uid-3');

  await assertFails(
    setDoc(
      doc(customer, 'orders/customer-order-3'),
      tableOrderPayload({
        tableSessionId: 'tgs-22',
        guestAuthUid: 'someone-else',
        customerId: 'customer-uid-3',
      }),
    ),
  );
});

test('anonymous uid cannot spoof a customer identity by claiming a real sign_in_provider is not required -> writing customerId = own uid with an anonymous token is still denied', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-23'),
      activeGuestSession({ guestAuthUid: 'guest-uid-23' }),
    );
  });
  // Deliberately the plain (non-'phone') authenticatedContext — an
  // anonymous-shaped token in every test in this suite unless
  // customerContext() is used.
  const guest = testEnv.authenticatedContext('guest-uid-23').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-23'),
      tableOrderPayload({
        tableSessionId: 'tgs-23',
        guestAuthUid: 'guest-uid-23',
        customerId: 'guest-uid-23',
      }),
    ),
  );
});

// ===== reservationContextId exact equality (Faz R.1C.2 §15) =====
//
// `tableGuestSessionMatchesOrderScope` now also requires
// `session.reservationContextId` to exactly equal `order.reservationContextId`
// (missing-field-safe via `.get(key, null)`, null included). Every test
// above that omits `reservationContextId` from both `activeGuestSession`/
// `tableOrderPayload` already proves the "both absent -> allow" case (the
// ordinary walk-in order) continues to pass unmodified — this section adds
// the cases that specifically exercise the new equality.

test('reservation-context session + matching order reservationContextId -> allow', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-1'),
      activeGuestSession({ guestAuthUid: 'guest-uid-rc-1', reservationContextId: 'RES_123' }),
    );
    // Faz R.3B §11 — a table-linked order create now also requires the
    // referenced Reservation to exist and be 'confirmed'.
    await setDoc(doc(db, 'reservations/RES_123'), reservationPayload({ status: 'confirmed' }));
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-1').firestore();

  await assertSucceeds(
    setDoc(
      doc(guest, 'orders/guest-order-rc-1'),
      tableOrderPayload({
        tableSessionId: 'tgs-rc-1',
        guestAuthUid: 'guest-uid-rc-1',
        reservationContextId: 'RES_123',
      }),
    ),
  );
});

test('reservation-context session + client omits reservationContextId on the order -> deny (cannot bypass by omission)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-2'),
      activeGuestSession({ guestAuthUid: 'guest-uid-rc-2', reservationContextId: 'RES_456' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-2').firestore();
  const payload = tableOrderPayload({ tableSessionId: 'tgs-rc-2', guestAuthUid: 'guest-uid-rc-2' });
  delete payload.reservationContextId; // not merely null - the key itself is absent

  await assertFails(setDoc(doc(guest, 'orders/guest-order-rc-2'), payload));
});

test('reservation-context session + client sends reservationContextId: null on the order -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-3'),
      activeGuestSession({ guestAuthUid: 'guest-uid-rc-3', reservationContextId: 'RES_789' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-3').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-rc-3'),
      tableOrderPayload({
        tableSessionId: 'tgs-rc-3',
        guestAuthUid: 'guest-uid-rc-3',
        reservationContextId: null,
      }),
    ),
  );
});

test('reservation-context session + client claims a different reservationContextId on the order -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-4'),
      activeGuestSession({ guestAuthUid: 'guest-uid-rc-4', reservationContextId: 'RES_REAL' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-4').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-rc-4'),
      tableOrderPayload({
        tableSessionId: 'tgs-rc-4',
        guestAuthUid: 'guest-uid-rc-4',
        reservationContextId: 'RES_FORGED',
      }),
    ),
  );
});

test('ordinary walk-in session (no reservationContextId) + client claims one on the order anyway -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-5'),
      activeGuestSession({ guestAuthUid: 'guest-uid-rc-5' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-5').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-rc-5'),
      tableOrderPayload({
        tableSessionId: 'tgs-rc-5',
        guestAuthUid: 'guest-uid-rc-5',
        reservationContextId: 'RES_UNINVITED',
      }),
    ),
  );
});

test('reservation-context session, real phone-verified customer variant, exact match -> allow', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-6'),
      activeGuestSession({ guestAuthUid: 'customer-uid-rc-6', reservationContextId: 'RES_CUSTOMER' }),
    );
    await setDoc(doc(db, 'reservations/RES_CUSTOMER'), reservationPayload({ status: 'confirmed' }));
  });
  const customer = customerContext('customer-uid-rc-6');

  await assertSucceeds(
    setDoc(
      doc(customer, 'orders/customer-order-rc-6'),
      tableOrderPayload({
        tableSessionId: 'tgs-rc-6',
        customerId: 'customer-uid-rc-6',
        guestAuthUid: 'customer-uid-rc-6',
        reservationContextId: 'RES_CUSTOMER',
      }),
    ),
  );
});

// ===== Faz R.3B §11/§14/§15 — reservationContextId orderable-state invariant =====
//
// A table-linked order create must never succeed once the referenced
// Reservation has gone terminal — the session itself is deliberately never
// deleted/killed on cancellation/completion/no-show (its own read/lifetime
// behavior is preserved), so this rule-level check against the
// Reservation's own live `status` is the actual enforcement.

test('reservation-context session referencing a CANCELLED reservation -> deny (terminal reservation, new linked order blocked)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-7'),
      activeGuestSession({ guestAuthUid: 'guest-uid-rc-7', reservationContextId: 'RES_CANCELLED' }),
    );
    await setDoc(doc(db, 'reservations/RES_CANCELLED'), reservationPayload({ status: 'cancelled' }));
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-7').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-rc-7'),
      tableOrderPayload({
        tableSessionId: 'tgs-rc-7',
        guestAuthUid: 'guest-uid-rc-7',
        reservationContextId: 'RES_CANCELLED',
      }),
    ),
  );
});

test('reservation-context session referencing a COMPLETED reservation -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-8'),
      activeGuestSession({ guestAuthUid: 'guest-uid-rc-8', reservationContextId: 'RES_COMPLETED' }),
    );
    await setDoc(doc(db, 'reservations/RES_COMPLETED'), reservationPayload({ status: 'completed' }));
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-8').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-rc-8'),
      tableOrderPayload({
        tableSessionId: 'tgs-rc-8',
        guestAuthUid: 'guest-uid-rc-8',
        reservationContextId: 'RES_COMPLETED',
      }),
    ),
  );
});

test('reservation-context session referencing a NO-SHOW reservation -> deny', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-9'),
      activeGuestSession({ guestAuthUid: 'guest-uid-rc-9', reservationContextId: 'RES_NOSHOW' }),
    );
    await setDoc(doc(db, 'reservations/RES_NOSHOW'), reservationPayload({ status: 'noShow' }));
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-9').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-rc-9'),
      tableOrderPayload({
        tableSessionId: 'tgs-rc-9',
        guestAuthUid: 'guest-uid-rc-9',
        reservationContextId: 'RES_NOSHOW',
      }),
    ),
  );
});

test('reservation-context session referencing a reservation that does not exist -> deny (fail closed, never assumed orderable)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-10'),
      activeGuestSession({ guestAuthUid: 'guest-uid-rc-10', reservationContextId: 'RES_MISSING' }),
    );
    // Deliberately never seeded — RES_MISSING does not exist.
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-10').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/guest-order-rc-10'),
      tableOrderPayload({
        tableSessionId: 'tgs-rc-10',
        guestAuthUid: 'guest-uid-rc-10',
        reservationContextId: 'RES_MISSING',
      }),
    ),
  );
});

test('ordinary walk-in dine-in order (no reservationContextId at all) is completely unaffected by the R.3B orderable-state check', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableGuestSessions/tgs-rc-11'), activeGuestSession({ guestAuthUid: 'guest-uid-rc-11' }));
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-11').firestore();

  await assertSucceeds(
    setDoc(
      doc(guest, 'orders/guest-order-rc-11'),
      tableOrderPayload({ tableSessionId: 'tgs-rc-11', guestAuthUid: 'guest-uid-rc-11' }),
    ),
  );
});

// ===== Read ownership =====

test('a table guest can read their own order via the immutable guestAuthUid snapshot', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-15'),
      activeGuestSession({ guestAuthUid: 'guest-uid-15' }),
    );
    await setDoc(
      doc(db, 'orders/guest-order-15'),
      tableOrderPayload({ tableSessionId: 'tgs-15', guestAuthUid: 'guest-uid-15' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-15').firestore();

  await assertSucceeds(getDoc(doc(guest, 'orders/guest-order-15')));
});

test('another table guest (different uid) cannot read someone else\'s guest order', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-15b'),
      activeGuestSession({ guestAuthUid: 'guest-uid-15b' }),
    );
    await setDoc(
      doc(db, 'orders/guest-order-15b'),
      tableOrderPayload({ tableSessionId: 'tgs-15b', guestAuthUid: 'guest-uid-15b' }),
    );
  });
  const otherGuest = testEnv.authenticatedContext('guest-uid-attacker-2').firestore();

  await assertFails(getDoc(doc(otherGuest, 'orders/guest-order-15b')));
});

test('a table guest can still read their own past order after their session has expired', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-15c'),
      activeGuestSession({
        guestAuthUid: 'guest-uid-15c',
        status: 'expired',
        expiresAt: Timestamp.fromDate(new Date(Date.now() - 60 * 1000)),
      }),
    );
    await setDoc(
      doc(db, 'orders/guest-order-15c'),
      tableOrderPayload({ tableSessionId: 'tgs-15c', guestAuthUid: 'guest-uid-15c' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-15c').firestore();

  await assertSucceeds(getDoc(doc(guest, 'orders/guest-order-15c')));
});

test('a table guest can still read their own order after the tableGuestSessions document is removed entirely — read never joins to it', async () => {
  // No tableGuestSessions document is ever created for this test at all —
  // proving `canReadAsTableGuest` has zero dependency on that collection,
  // unlike the pre-Phase-3.1 join-based design.
  await seed(async (db) => {
    await setDoc(
      doc(db, 'orders/guest-order-15d'),
      tableOrderPayload({ tableSessionId: 'tgs-does-not-exist-anymore', guestAuthUid: 'guest-uid-15d' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-15d').firestore();

  await assertSucceeds(getDoc(doc(guest, 'orders/guest-order-15d')));
});

test('an authenticated customer can read their own table order via the existing customerId ownership path', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'orders/customer-order-read-1'),
      tableOrderPayload({
        tableSessionId: 'tgs-does-not-matter-for-read',
        guestAuthUid: 'customer-uid-4',
        customerId: 'customer-uid-4',
      }),
    );
  });
  const customer = customerContext('customer-uid-4');

  await assertSucceeds(getDoc(doc(customer, 'orders/customer-order-read-1')));
});

test('a staff member of a different organization cannot read a table guest order belonging to another tenant (cross-tenant read denied)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-16'),
      activeGuestSession({ guestAuthUid: 'guest-uid-16' }),
    );
    await setDoc(
      doc(db, 'orders/guest-order-16'),
      tableOrderPayload({ tableSessionId: 'tgs-16', guestAuthUid: 'guest-uid-16' }),
    );
  });
  const otherOrgStaff = testEnv
    .authenticatedContext('staff-other-org', { organizationAccess: ['org-2'] })
    .firestore();

  await assertFails(getDoc(doc(otherOrgStaff, 'orders/guest-order-16')));
});

test('a customer can read and update only their own profile fields, never role/status fields', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customers/alice'), {
      displayName: 'Alice',
      email: 'alice@example.com',
    });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();
  const bob = testEnv.authenticatedContext('bob', {}).firestore();

  await assertSucceeds(getDoc(doc(alice, 'customers/alice')));
  await assertFails(getDoc(doc(bob, 'customers/alice')));
  await assertSucceeds(
    updateDoc(doc(alice, 'customers/alice'), { displayName: 'Alice Updated' }),
  );
});

test('a customer cannot self-provision their own customer document (server-only create)', async () => {
  // Uses a uid no earlier test has seeded — otherwise this setDoc would be
  // an update (allowed for displayName) rather than a create, since
  // Firestore emulator data persists across tests within this suite.
  const carol = testEnv.authenticatedContext('carol', {}).firestore();

  await assertFails(
    setDoc(doc(carol, 'customers/carol'), { displayName: 'Carol' }),
  );
});

test('a platform member without an active support grant cannot read tenant data outside their own scope', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'organizations/org-1'), { name: 'Abaküs' });
  });
  const platformAdmin = testEnv
    .authenticatedContext('platform-1', { platformRole: 'platformAdministrator' })
    .firestore();

  await assertFails(getDoc(doc(platformAdmin, 'organizations/org-1')));
});

test('a platform member WITH an active, non-expired support grant can read that tenant\'s data', async () => {
  const future = new Date(Date.now() + 60 * 60 * 1000);
  await seed(async (db) => {
    await setDoc(doc(db, 'organizations/org-1'), { name: 'Abaküs' });
    await setDoc(doc(db, 'supportGrants/org-1_platform-1'), {
      organizationId: 'org-1',
      platformMemberId: 'platform-1',
      reason: 'Debugging a reported sync failure (ticket #123)',
      expiresAt: future,
    });
  });
  const platformAdmin = testEnv
    .authenticatedContext('platform-1', { platformRole: 'platformAdministrator' })
    .firestore();

  await assertSucceeds(getDoc(doc(platformAdmin, 'organizations/org-1')));
});

test('an EXPIRED support grant no longer grants access — time-limited, not permanent', async () => {
  const past = new Date(Date.now() - 60 * 60 * 1000);
  await seed(async (db) => {
    await setDoc(doc(db, 'organizations/org-1'), { name: 'Abaküs' });
    await setDoc(doc(db, 'supportGrants/org-1_platform-1'), {
      organizationId: 'org-1',
      platformMemberId: 'platform-1',
      reason: 'Old investigation, should no longer apply',
      expiresAt: past,
    });
  });
  const platformAdmin = testEnv
    .authenticatedContext('platform-1', { platformRole: 'platformAdministrator' })
    .firestore();

  await assertFails(getDoc(doc(platformAdmin, 'organizations/org-1')));
});

test('a tenant role claim never grants a platform action, and vice versa — the two claim namespaces never cross', async () => {
  const tenantOwner = testEnv
    .authenticatedContext('owner-1', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['tenantOwner'] },
    })
    .firestore();

  // tenantOwner has no platformRole claim at all, so platformMembers is
  // unreachable regardless of how senior they are within their own tenant.
  await assertFails(getDoc(doc(tenantOwner, 'platformMembers/platform-1')));
});

test('an unlisted collection defaults to fully denied (fail closed)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'somethingNobodyThoughtOf/doc-1'), { value: 1 });
  });
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(getDoc(doc(alice, 'somethingNobodyThoughtOf/doc-1')));
});

test('a device token is only readable/writable by its owning user', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'deviceTokens/token-1'), {
      uid: 'alice',
      organizationId: 'org-1',
      token: 'fcm-token-value',
    });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();
  const bob = testEnv.authenticatedContext('bob', {}).firestore();

  await assertSucceeds(getDoc(doc(alice, 'deviceTokens/token-1')));
  await assertFails(getDoc(doc(bob, 'deviceTokens/token-1')));
});

test('a device token cannot be created directly by any client, even under the caller\'s own uid — Faz R.3C.1, Cloud Function only', async () => {
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  // Faz R.3C.1: `create` moved Cloud-Function-only (`registerDeviceToken.ts`)
  // — a spoofed uid was already denied under the prior R.3C rule, but so
  // was every direct client create, including under the caller's own uid,
  // once the reassociation audit found that a per-document rule cannot
  // detect a duplicate `token` *value* already active under a different
  // owner (see `registerDeviceToken.ts`'s own doc comment).
  await assertFails(
    setDoc(doc(alice, 'deviceTokens/token-spoof'), {
      uid: 'bob',
      organizationId: 'org-1',
      token: 'fcm-token-value',
    }),
  );
  await assertFails(
    setDoc(doc(alice, 'deviceTokens/token-own'), {
      uid: 'alice',
      organizationId: 'org-1',
      token: 'fcm-token-value',
    }),
  );
});

test('a device token can still be revoked (updated) directly by its owner — logout self-revocation is unaffected by the create-rule tightening', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'deviceTokens/token-owned-by-alice'), {
      uid: 'alice',
      organizationId: 'org-1',
      token: 'fcm-token-value',
      platform: 'android',
      registeredAt: new Date().toISOString(),
      revokedAt: null,
    });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertSucceeds(
    setDoc(
      doc(alice, 'deviceTokens/token-owned-by-alice'),
      { revokedAt: new Date().toISOString() },
      { merge: true },
    ),
  );
});

test('reservationEvents (the notification outbox) is fully client-write-denied — Faz R.3C', async () => {
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertFails(
    setDoc(doc(alice, 'reservationEvents/event-1'), {
      type: 'reservationConfirmed',
      reservationId: 'reservation-1',
    }),
  );
});

test('reservationNotificationDeliveries is fully client-denied (default-deny, no rule needed) — Faz R.3C', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'reservationNotificationDeliveries/event-1'), {
      status: 'sent',
    });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertFails(getDoc(doc(alice, 'reservationNotificationDeliveries/event-1')));
  await assertFails(
    setDoc(doc(alice, 'reservationNotificationDeliveries/event-2'), { status: 'sent' }),
  );
});

test('a deletion request can be created by the requesting user for themselves only, starting in pendingVerification', async () => {
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertSucceeds(
    setDoc(doc(alice, 'deletionRequests/req-1'), {
      uid: 'alice',
      status: 'pendingVerification',
    }),
  );
  await assertFails(
    setDoc(doc(alice, 'deletionRequests/req-2'), {
      uid: 'bob',
      status: 'pendingVerification',
    }),
  );
});

test('a client cannot transition their own deletion request\'s status directly — every status change after creation is server-authoritative', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'deletionRequests/req-1'), {
      uid: 'alice',
      status: 'pendingVerification',
    });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertFails(
    updateDoc(doc(alice, 'deletionRequests/req-1'), { status: 'completed' }),
  );
});

// =====================================================================
// Faz D.3.1 — authenticated in-app Gel Al (takeaway) order create is now
// fully removed from client-reachable rules. `submitTakeawayOrder`
// (Admin SDK) is the sole create path; a direct client `setDoc` — no
// matter how well-formed, valid-shaped the payload is — must always be
// denied. Read access is unaffected (still the same generic
// `customerId == request.auth.uid` rule every channel relies on), and is
// exercised here specifically against an Admin-SDK-style write
// (`seed()`'s `withSecurityRulesDisabled`, the same bypass mechanism a
// real Cloud Function's Admin SDK write uses) to prove a
// backend-created takeaway order is genuinely readable by its owner.
// =====================================================================

function authenticatedTakeawayOrderPayload(overrides = {}) {
  return {
    organizationId: 'org-1',
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    customerId: 'takeaway-customer-default',
    channel: 'takeaway',
    status: 'pendingConfirmation',
    pickupMode: 'scheduled',
    pickupTimeTimestamp: Timestamp.fromDate(
      new Date(Date.now() + 25 * 60 * 1000),
    ),
    contactFirstName: 'Ada',
    contactLastName: 'Yılmaz',
    contactPhone: '+905551112233',
    pricing: { grandTotal: { minorUnits: 12000, currencyCode: 'TRY' } },
    ...overrides,
  };
}

test('authenticated takeaway: direct client create is denied even for a fully well-formed, previously-valid payload — no direct-create path exists anymore (Faz D.3.1)', async () => {
  const customer = customerContext('takeaway-customer-1');

  await assertFails(
    setDoc(
      doc(customer, 'orders/takeaway-order-1'),
      authenticatedTakeawayOrderPayload({ customerId: 'takeaway-customer-1' }),
    ),
  );
});

test('authenticated takeaway: direct client create is denied for a customerId-matched payload from an org-member/staff-shaped write too (no branch anywhere in the rules file can satisfy a channel: takeaway create)', async () => {
  const customer = customerContext('takeaway-customer-2');

  await assertFails(
    setDoc(
      doc(customer, 'orders/takeaway-order-2'),
      authenticatedTakeawayOrderPayload({
        customerId: 'takeaway-customer-2',
        // Even claiming org-member-shaped fields changes nothing — the
        // isOrgMember() branch requires an actual organizationAccess
        // claim, which this real-customer context doesn't have either.
        status: 'created',
      }),
    ),
  );
});

test('authenticated takeaway: an anonymous technical identity is also denied (unchanged — still no guest takeaway create path in rules; that remains Admin-SDK-only via submitTakeawayOrder too, Faz D.2/D.3)', async () => {
  const anon = testEnv.authenticatedContext('anon-uid-1').firestore();

  await assertFails(
    setDoc(
      doc(anon, 'orders/takeaway-order-3'),
      authenticatedTakeawayOrderPayload({ customerId: 'anon-uid-1' }),
    ),
  );
});

test('authenticated takeaway: a real customer can read their own backend-created (Admin-SDK-written) takeaway order — the same generic customerId == request.auth.uid read rule every other channel already relies on, unaffected by removing the create branch', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'orders/takeaway-order-16'),
      authenticatedTakeawayOrderPayload({ customerId: 'takeaway-customer-15' }),
    );
  });
  const customer = customerContext('takeaway-customer-15');

  await assertSucceeds(getDoc(doc(customer, 'orders/takeaway-order-16')));
});

test('authenticated takeaway: another customer cannot read someone else\'s backend-created takeaway order', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'orders/takeaway-order-17'),
      authenticatedTakeawayOrderPayload({ customerId: 'takeaway-customer-16' }),
    );
  });
  const otherCustomer = customerContext('takeaway-customer-attacker');

  await assertFails(getDoc(doc(otherCustomer, 'orders/takeaway-order-17')));
});

// =====================================================================
// Faz D.3.1.1 — audit-closing coverage. Two real gaps found while
// verifying the 8 required security behaviors against the *current*
// (post-D.3.1) test file, added here, nothing else re-added:
//
// 1. The generic `isOrgMember(...)` create branch (line ~410 in
//    firestore.rules) has no `channel` check at all — it was, and still
//    is, staff/POS's own create path for ANY channel, takeaway included.
//    Every existing staff-create test (above) omits `channel` entirely,
//    so "staff create is unaffected by the takeaway removal" was true by
//    inspection but not explicitly, directly proven for `channel:
//    'takeaway'` specifically. Added below.
// 2. `canReadAsTableGuest` (channel-agnostic: `guestAuthUid ==
//    request.auth.uid`, no channel check) already covers a
//    backend-created QR-guest TAKEAWAY order exactly like it covers a
//    dine-in table guest order — but no test exercised it for the
//    takeaway shape (`customerId: null`, `guestAuthUid` set,
//    `channel: 'takeaway'`, the exact shape `submitTakeawayOrder`'s QR
//    guest branch writes, Faz D.2/D.3). Added below.
// =====================================================================

test('staff create is unaffected by the takeaway direct-create removal — an org member can still create a channel: takeaway order via the untouched, channel-agnostic isOrgMember branch', async () => {
  const staff = testEnv
    .authenticatedContext('staff-takeaway-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(
    setDoc(doc(staff, 'orders/staff-takeaway-order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      channel: 'takeaway',
      status: 'created',
    }),
  );
});

function takeawayGuestOrderPayload(overrides = {}) {
  return {
    organizationId: 'org-1',
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    customerId: null,
    guestAuthUid: 'takeaway-guest-uid-default',
    channel: 'takeaway',
    status: 'pendingConfirmation',
    pickupMode: 'asap',
    pickupTime: null,
    contactFirstName: 'Ada',
    contactLastName: 'Yılmaz',
    contactPhone: '+905551112233',
    pricing: { grandTotal: { minorUnits: 12000, currencyCode: 'TRY' } },
    ...overrides,
  };
}

test('QR guest takeaway: the owning guest can read their own backend-created (Admin-SDK-written) takeaway order via the immutable guestAuthUid snapshot', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'orders/takeaway-guest-order-1'),
      takeawayGuestOrderPayload({ guestAuthUid: 'takeaway-guest-uid-1' }),
    );
  });
  const guest = testEnv.authenticatedContext('takeaway-guest-uid-1').firestore();

  await assertSucceeds(getDoc(doc(guest, 'orders/takeaway-guest-order-1')));
});

test('QR guest takeaway: another uid cannot read someone else\'s backend-created QR-guest takeaway order', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'orders/takeaway-guest-order-2'),
      takeawayGuestOrderPayload({ guestAuthUid: 'takeaway-guest-uid-2' }),
    );
  });
  const attacker = testEnv.authenticatedContext('takeaway-guest-uid-attacker').firestore();

  await assertFails(getDoc(doc(attacker, 'orders/takeaway-guest-order-2')));
});

// ---------------------------------------------------------------------
// Faz D.2 — takeawayGuestSessions / takeawayQrCodes rules. Mirrors the
// existing tableGuestSessions read-ownership tests above exactly — same
// rule shape (`allow read: if isSignedIn() && resource.data.guestAuthUid
// == request.auth.uid`, `allow write: if false`) — plus explicit
// create/update/delete denial tests and a direct read denial for
// `takeawayQrCodes` (which has no match block of its own at all, covered
// by the fail-closed catch-all).
// ---------------------------------------------------------------------

test('takeawayGuestSessions: the owning guest can read their own session', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'takeawayGuestSessions/tws-1'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      guestAuthUid: 'takeaway-guest-1',
      status: 'active',
      qrTokenId: 'qr-1',
    });
  });
  const guest = testEnv.authenticatedContext('takeaway-guest-1').firestore();

  await assertSucceeds(getDoc(doc(guest, 'takeawayGuestSessions/tws-1')));
});

test('takeawayGuestSessions: a different uid cannot read someone else\'s session', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'takeawayGuestSessions/tws-2'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      guestAuthUid: 'takeaway-guest-2',
      status: 'active',
      qrTokenId: 'qr-2',
    });
  });
  const attacker = testEnv.authenticatedContext('takeaway-guest-attacker').firestore();

  await assertFails(getDoc(doc(attacker, 'takeawayGuestSessions/tws-2')));
});

test('takeawayGuestSessions: an unauthenticated caller cannot read any session', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'takeawayGuestSessions/tws-3'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      guestAuthUid: 'takeaway-guest-3',
      status: 'active',
      qrTokenId: 'qr-3',
    });
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'takeawayGuestSessions/tws-3')));
});

test('takeawayGuestSessions: a client cannot create a session directly, even one that claims their own uid as guestAuthUid', async () => {
  const guest = testEnv.authenticatedContext('takeaway-guest-4').firestore();

  await assertFails(
    setDoc(doc(guest, 'takeawayGuestSessions/tws-4'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      guestAuthUid: 'takeaway-guest-4',
      status: 'active',
      qrTokenId: 'qr-4',
    }),
  );
});

test('takeawayGuestSessions: the owning guest cannot update their own session directly', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'takeawayGuestSessions/tws-5'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      guestAuthUid: 'takeaway-guest-5',
      status: 'active',
      qrTokenId: 'qr-5',
    });
  });
  const guest = testEnv.authenticatedContext('takeaway-guest-5').firestore();

  await assertFails(
    updateDoc(doc(guest, 'takeawayGuestSessions/tws-5'), { status: 'closed' }),
  );
});

test('takeawayGuestSessions: the owning guest cannot delete their own session directly', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'takeawayGuestSessions/tws-6'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      guestAuthUid: 'takeaway-guest-6',
      status: 'active',
      qrTokenId: 'qr-6',
    });
  });
  const guest = testEnv.authenticatedContext('takeaway-guest-6').firestore();

  await assertFails(deleteDoc(doc(guest, 'takeawayGuestSessions/tws-6')));
});

test('takeawayQrCodes: direct client read is denied — no match block of its own, covered by the fail-closed catch-all', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'takeawayQrCodes/qr-direct-1'), {
      opaqueToken: 'TOKEN-DIRECT-READ-ATTEMPT',
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      status: 'active',
    });
  });
  const someone = testEnv.authenticatedContext('anyone-uid').firestore();

  await assertFails(getDoc(doc(someone, 'takeawayQrCodes/qr-direct-1')));
});

test('takeawayQrCodes: direct client write is denied', async () => {
  const someone = testEnv.authenticatedContext('anyone-uid-2').firestore();

  await assertFails(
    setDoc(doc(someone, 'takeawayQrCodes/qr-direct-2'), {
      opaqueToken: 'TOKEN-DIRECT-WRITE-ATTEMPT',
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      status: 'active',
    }),
  );
});

// =========================================================================
// Reservations — Faz R.1A (docs/decisions.md ADR-027 Faz R.0-R.0.7 design).
// `submitReservation` (Admin SDK) is the sole writer of `reservations`;
// `reservationAreas`/`reservationPolicies`/`reservationHolds`/
// `reservationSlotOccupancy` have no match block of their own in
// firestore.rules at all — covered by the fail-closed catch-all, mirroring
// `tableQrCodes`/`takeawayQrCodes`'s own precedent. Every test below proves
// that structural claim directly, rather than assuming it.
// =========================================================================

function reservationPayload(overrides = {}) {
  return {
    organizationId: 'org-1',
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    areaId: 'garden',
    customerId: 'reservation-customer-default',
    contactFirstName: 'Ada',
    contactLastName: 'Yılmaz',
    contactPhone: '+905551112233',
    partySize: 2,
    requestedTime: Timestamp.fromDate(new Date(Date.now() + 60 * 60 * 1000)),
    requestedAreaId: 'garden',
    requestedAvailabilityAtSubmission: 'available',
    status: 'pendingRestaurantApproval',
    activeHoldId: null,
    responseDeadlineAt: Timestamp.fromDate(new Date(Date.now() + 60 * 60 * 1000)),
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...overrides,
  };
}

test('reservations: the owning customer can read their own reservation', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservations/res-owner-read-1'),
      reservationPayload({ customerId: 'reservation-customer-1' }),
    );
  });
  const customer = testEnv.authenticatedContext('reservation-customer-1').firestore();

  await assertSucceeds(getDoc(doc(customer, 'reservations/res-owner-read-1')));
});

test('reservations: an org member (staff) can read a reservation belonging to their tenant', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservations/res-staff-read-1'),
      reservationPayload({ customerId: 'reservation-customer-2' }),
    );
  });
  const staff = testEnv
    .authenticatedContext('staff-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(getDoc(doc(staff, 'reservations/res-staff-read-1')));
});

test('reservations: another customer cannot read someone else\'s reservation', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservations/res-cross-customer-1'),
      reservationPayload({ customerId: 'reservation-customer-3' }),
    );
  });
  const attacker = testEnv.authenticatedContext('reservation-customer-attacker').firestore();

  await assertFails(getDoc(doc(attacker, 'reservations/res-cross-customer-1')));
});

test('reservations: an org member of a different tenant cannot read this reservation — cross-tenant read denied', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservations/res-cross-tenant-1'),
      reservationPayload({ organizationId: 'org-1', customerId: 'reservation-customer-4' }),
    );
  });
  const otherTenantStaff = testEnv
    .authenticatedContext('staff-org2', { organizationAccess: ['org-2'] })
    .firestore();

  await assertFails(getDoc(doc(otherTenantStaff, 'reservations/res-cross-tenant-1')));
});

test('reservations: an unauthenticated caller cannot read any reservation', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservations/res-unauth-1'),
      reservationPayload({ customerId: 'reservation-customer-5' }),
    );
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'reservations/res-unauth-1')));
});

test('reservations: direct client create is denied — even a well-formed, self-owned payload — submitReservation (Admin SDK) is the sole writer', async () => {
  const customer = testEnv.authenticatedContext('reservation-customer-6').firestore();

  await assertFails(
    setDoc(
      doc(customer, 'reservations/res-direct-create-1'),
      reservationPayload({ customerId: 'reservation-customer-6' }),
    ),
  );
});

test('reservations: direct client update is denied, even by the owning customer', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservations/res-direct-update-1'),
      reservationPayload({ customerId: 'reservation-customer-7' }),
    );
  });
  const customer = testEnv.authenticatedContext('reservation-customer-7').firestore();

  await assertFails(
    updateDoc(doc(customer, 'reservations/res-direct-update-1'), { status: 'confirmed' }),
  );
});

test('reservations: direct client delete is denied', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservations/res-direct-delete-1'),
      reservationPayload({ customerId: 'reservation-customer-8' }),
    );
  });
  const customer = testEnv.authenticatedContext('reservation-customer-8').firestore();

  await assertFails(deleteDoc(doc(customer, 'reservations/res-direct-delete-1')));
});

// Reservation change proposals — Faz R.1B (docs/decisions.md ADR-027 Faz
// R.1B design). `respondToReservation` (create) / `respondToProposedChange`
// (accept/reject) / `reservationSweep` (expire) are the sole writers.
function reservationChangeProposalPayload(overrides = {}) {
  return {
    proposalId: 'proposal-default',
    reservationId: 'res-default',
    organizationId: 'org-1',
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    proposedAreaId: 'garden',
    status: 'pendingCustomerResponse',
    holdId: 'hold-default',
    ...overrides,
  };
}

test('reservationChangeProposals: an org member (staff) can read a proposal belonging to their tenant', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservationChangeProposals/proposal-staff-read-1'),
      reservationChangeProposalPayload({ organizationId: 'org-1' }),
    );
  });
  const staff = testEnv
    .authenticatedContext('staff-2', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(getDoc(doc(staff, 'reservationChangeProposals/proposal-staff-read-1')));
});

test('reservationChangeProposals: an org member of a different tenant cannot read this proposal — cross-tenant read denied', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservationChangeProposals/proposal-cross-tenant-1'),
      reservationChangeProposalPayload({ organizationId: 'org-1' }),
    );
  });
  const otherTenantStaff = testEnv
    .authenticatedContext('staff-3', { organizationAccess: ['org-2'] })
    .firestore();

  await assertFails(getDoc(doc(otherTenantStaff, 'reservationChangeProposals/proposal-cross-tenant-1')));
});

test('reservationChangeProposals: the reservation\'s own customer cannot read a proposal directly — no UI exists yet, not opened speculatively', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservationChangeProposals/proposal-customer-read-1'),
      reservationChangeProposalPayload({ organizationId: 'org-1' }),
    );
  });
  const customer = testEnv.authenticatedContext('reservation-customer-proposal-1').firestore();

  await assertFails(getDoc(doc(customer, 'reservationChangeProposals/proposal-customer-read-1')));
});

test('reservationChangeProposals: an unauthenticated caller cannot read any proposal', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservationChangeProposals/proposal-unauth-1'),
      reservationChangeProposalPayload({ organizationId: 'org-1' }),
    );
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'reservationChangeProposals/proposal-unauth-1')));
});

test('reservationChangeProposals: direct client create is denied — respondToReservation (Admin SDK) is the sole writer', async () => {
  const staff = testEnv
    .authenticatedContext('staff-4', { organizationAccess: ['org-1'], roles: { 'org-1': ['manager'] } })
    .firestore();

  await assertFails(
    setDoc(
      doc(staff, 'reservationChangeProposals/proposal-direct-create-1'),
      reservationChangeProposalPayload({ organizationId: 'org-1' }),
    ),
  );
});

test('reservationChangeProposals: direct client update is denied, even by org staff with manageReservations-shaped claims', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservationChangeProposals/proposal-direct-update-1'),
      reservationChangeProposalPayload({ organizationId: 'org-1' }),
    );
  });
  const staff = testEnv
    .authenticatedContext('staff-5', { organizationAccess: ['org-1'], roles: { 'org-1': ['manager'] } })
    .firestore();

  await assertFails(
    updateDoc(doc(staff, 'reservationChangeProposals/proposal-direct-update-1'), { status: 'accepted' }),
  );
});

test('reservationChangeProposals: direct client delete is denied', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'reservationChangeProposals/proposal-direct-delete-1'),
      reservationChangeProposalPayload({ organizationId: 'org-1' }),
    );
  });
  const staff = testEnv
    .authenticatedContext('staff-6', { organizationAccess: ['org-1'], roles: { 'org-1': ['manager'] } })
    .firestore();

  await assertFails(deleteDoc(doc(staff, 'reservationChangeProposals/proposal-direct-delete-1')));
});

test('reservationAreas: direct client read is denied — no match block of its own, covered by the fail-closed catch-all', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'reservationAreas/garden'), {
      branchId: 'branch-1',
      displayName: 'Bahçe',
      isActive: true,
      capacity: 40,
    });
  });
  const someone = testEnv.authenticatedContext('reservation-area-reader').firestore();

  await assertFails(getDoc(doc(someone, 'reservationAreas/garden')));
});

test('reservationAreas: direct client write is denied', async () => {
  const someone = testEnv.authenticatedContext('reservation-area-writer').firestore();

  await assertFails(
    setDoc(doc(someone, 'reservationAreas/hijacked'), {
      branchId: 'branch-1',
      displayName: 'Hijacked',
      isActive: true,
      capacity: 999,
    }),
  );
});

test('reservationPolicies: direct client read is denied', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'reservationPolicies/branch-1'), { enabled: true, maxPartySize: 12 });
  });
  const someone = testEnv.authenticatedContext('reservation-policy-reader').firestore();

  await assertFails(getDoc(doc(someone, 'reservationPolicies/branch-1')));
});

test('reservationPolicies: direct client write is denied', async () => {
  const someone = testEnv.authenticatedContext('reservation-policy-writer').firestore();

  await assertFails(
    setDoc(doc(someone, 'reservationPolicies/branch-1'), { enabled: true, maxPartySize: 999 }),
  );
});

test('reservationHolds: direct client read is denied', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'reservationHolds/hold-1'), {
      reservationId: 'res-x',
      status: 'active',
      purpose: 'initialRequest',
      partySize: 2,
    });
  });
  const someone = testEnv.authenticatedContext('reservation-hold-reader').firestore();

  await assertFails(getDoc(doc(someone, 'reservationHolds/hold-1')));
});

test('reservationHolds: direct client write is denied — a client cannot fabricate its own held capacity', async () => {
  const someone = testEnv.authenticatedContext('reservation-hold-writer').firestore();

  await assertFails(
    setDoc(doc(someone, 'reservationHolds/hold-forged'), {
      reservationId: 'res-forged',
      status: 'active',
      purpose: 'initialRequest',
      partySize: 999,
    }),
  );
});

test('reservationSlotOccupancy: direct client read is denied', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'reservationSlotOccupancy/branch-1__garden__2026-08-13T20:00:00.000Z'), {
      confirmedPartySize: 0,
      heldPartySize: 2,
      capacity: 40,
    });
  });
  const someone = testEnv.authenticatedContext('reservation-occupancy-reader').firestore();

  await assertFails(
    getDoc(doc(someone, 'reservationSlotOccupancy/branch-1__garden__2026-08-13T20:00:00.000Z')),
  );
});

test('reservationSlotOccupancy: direct client write is denied — a client cannot forge capacity headroom for itself', async () => {
  const someone = testEnv.authenticatedContext('reservation-occupancy-writer').firestore();

  await assertFails(
    setDoc(doc(someone, 'reservationSlotOccupancy/branch-1__garden__2026-08-13T21:00:00.000Z'), {
      confirmedPartySize: 0,
      heldPartySize: -999, // even an attempt to *free* capacity by writing a negative value is denied
      capacity: 40,
    }),
  );
});

// Physical table assignment data — Faz R.1C.1 (docs/decisions.md ADR-027
// Faz R.1C.1 design). `assignReservationTable` (Admin SDK) is the sole
// writer of all three collections below.

test('reservationTableOccupancy: an org member (staff) can read a bucket belonging to their tenant', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'reservationTableOccupancy/table-1__1755000000000'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      assignedReservationId: 'res-x',
    });
  });
  const staff = testEnv
    .authenticatedContext('table-occupancy-staff', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(getDoc(doc(staff, 'reservationTableOccupancy/table-1__1755000000000')));
});

test('reservationTableOccupancy: an org member of a different tenant cannot read this bucket — cross-tenant read denied', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'reservationTableOccupancy/table-2__1755000000000'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-2',
      assignedReservationId: 'res-y',
    });
  });
  const otherTenantStaff = testEnv
    .authenticatedContext('table-occupancy-other-tenant', { organizationAccess: ['org-2'] })
    .firestore();

  await assertFails(getDoc(doc(otherTenantStaff, 'reservationTableOccupancy/table-2__1755000000000')));
});

test('reservationTableOccupancy: an unauthenticated caller cannot read any bucket', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'reservationTableOccupancy/table-3__1755000000000'), {
      organizationId: 'org-1',
      assignedReservationId: 'res-z',
    });
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'reservationTableOccupancy/table-3__1755000000000')));
});

test('reservationTableOccupancy: direct client write is denied — a client cannot fabricate its own physical-table lock', async () => {
  const staff = testEnv
    .authenticatedContext('table-occupancy-writer', { organizationAccess: ['org-1'], roles: { 'org-1': ['manager'] } })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'reservationTableOccupancy/table-forged__1755000000000'), {
      organizationId: 'org-1',
      tableId: 'table-forged',
      assignedReservationId: 'res-forged',
    }),
  );
});

test('reservationTableProtections: an org member (staff) can read a protection record belonging to their tenant', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'reservationTableProtections/res-protection-1'), {
      reservationId: 'res-protection-1',
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      active: true,
    });
  });
  const staff = testEnv
    .authenticatedContext('table-protection-staff', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(getDoc(doc(staff, 'reservationTableProtections/res-protection-1')));
});

test('reservationTableProtections: an org member of a different tenant cannot read this record — cross-tenant read denied', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'reservationTableProtections/res-protection-2'), {
      reservationId: 'res-protection-2',
      organizationId: 'org-1',
      active: true,
    });
  });
  const otherTenantStaff = testEnv
    .authenticatedContext('table-protection-other-tenant', { organizationAccess: ['org-2'] })
    .firestore();

  await assertFails(getDoc(doc(otherTenantStaff, 'reservationTableProtections/res-protection-2')));
});

test('reservationTableProtections: direct client write is denied', async () => {
  const staff = testEnv
    .authenticatedContext('table-protection-writer', { organizationAccess: ['org-1'], roles: { 'org-1': ['manager'] } })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'reservationTableProtections/res-forged'), {
      reservationId: 'res-forged',
      organizationId: 'org-1',
      active: true,
    }),
  );
});

test('tableProtectionMinuteBuckets: an org member (staff) can read a minute bucket belonging to their tenant', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableProtectionMinuteBuckets/table-1__29250000'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      epochMinute: 29250000,
      reservationIds: ['res-x'],
    });
  });
  const staff = testEnv
    .authenticatedContext('minute-bucket-staff', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(getDoc(doc(staff, 'tableProtectionMinuteBuckets/table-1__29250000')));
});

test('tableProtectionMinuteBuckets: an org member of a different tenant cannot read this bucket — cross-tenant read denied', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableProtectionMinuteBuckets/table-2__29250000'), {
      organizationId: 'org-1',
      reservationIds: ['res-y'],
    });
  });
  const otherTenantStaff = testEnv
    .authenticatedContext('minute-bucket-other-tenant', { organizationAccess: ['org-2'] })
    .firestore();

  await assertFails(getDoc(doc(otherTenantStaff, 'tableProtectionMinuteBuckets/table-2__29250000')));
});

test('tableProtectionMinuteBuckets: direct client write is denied — a client cannot forge or clear reservationIds membership', async () => {
  const staff = testEnv
    .authenticatedContext('minute-bucket-writer', { organizationAccess: ['org-1'], roles: { 'org-1': ['manager'] } })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'tableProtectionMinuteBuckets/table-forged__29250000'), {
      organizationId: 'org-1',
      reservationIds: ['res-forged'],
    }),
  );
});

// Active reservation table context — Faz R.1C.2 §4/§19.
// `openReservationTable`/`closeReservationTable` (Admin SDK) are the sole
// writers.

test('activeReservationTableContext: an org member (staff) can read a context belonging to their tenant', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'activeReservationTableContext/table-ctx-1'), {
      reservationId: 'res-ctx-1',
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-ctx-1',
      active: true,
    });
  });
  const staff = testEnv
    .authenticatedContext('context-staff-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(getDoc(doc(staff, 'activeReservationTableContext/table-ctx-1')));
});

test('activeReservationTableContext: an org member of a different tenant cannot read this context — cross-tenant read denied', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'activeReservationTableContext/table-ctx-2'), {
      reservationId: 'res-ctx-2',
      organizationId: 'org-1',
      active: true,
    });
  });
  const otherTenantStaff = testEnv
    .authenticatedContext('context-staff-2', { organizationAccess: ['org-2'] })
    .firestore();

  await assertFails(getDoc(doc(otherTenantStaff, 'activeReservationTableContext/table-ctx-2')));
});

test('activeReservationTableContext: an unauthenticated caller cannot read any context', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'activeReservationTableContext/table-ctx-3'), {
      reservationId: 'res-ctx-3',
      organizationId: 'org-1',
      active: true,
    });
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'activeReservationTableContext/table-ctx-3')));
});

test('activeReservationTableContext: direct client write is denied — a client cannot forge a table-open for itself', async () => {
  const staff = testEnv
    .authenticatedContext('context-writer', { organizationAccess: ['org-1'], roles: { 'org-1': ['manager'] } })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'activeReservationTableContext/table-ctx-forged'), {
      reservationId: 'res-forged',
      organizationId: 'org-1',
      active: true,
    }),
  );
});

test('activeReservationTableContext: direct client update is denied, even by org staff', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'activeReservationTableContext/table-ctx-4'), {
      reservationId: 'res-ctx-4',
      organizationId: 'org-1',
      active: true,
    });
  });
  const staff = testEnv
    .authenticatedContext('context-updater', { organizationAccess: ['org-1'], roles: { 'org-1': ['manager'] } })
    .firestore();

  await assertFails(updateDoc(doc(staff, 'activeReservationTableContext/table-ctx-4'), { active: false }));
});

// tableGuestSessions.reservationContextId immutability — already covered
// structurally by the collection's own `allow write: if false` (no client
// write path exists at all), proven directly here rather than only
// inferred from the blanket rule.

test('tableGuestSessions: a client cannot update reservationContextId on their own session', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableGuestSessions/tgs-immutable-1'), activeGuestSession({
      guestAuthUid: 'guest-immutable-1',
      reservationContextId: null,
    }));
  });
  const guest = testEnv.authenticatedContext('guest-immutable-1').firestore();

  await assertFails(
    updateDoc(doc(guest, 'tableGuestSessions/tgs-immutable-1'), { reservationContextId: 'RES_INJECTED' }),
  );
});

// ---------------------------------------------------------------------
// customerAddresses (Faz P.2) — a customer manages only their own saved
// addresses; provider-verification fields are server-owned.
// ---------------------------------------------------------------------

test('customerAddresses: owner can read their own address, a different customer cannot (req 14)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerAddresses/address-1'), {
      uid: 'alice',
      label: 'Ev',
      verificationStatus: 'verified',
    });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();
  const bob = testEnv.authenticatedContext('bob', {}).firestore();

  await assertSucceeds(getDoc(doc(alice, 'customerAddresses/address-1')));
  await assertFails(getDoc(doc(bob, 'customerAddresses/address-1')));
});

test('customerAddresses: owner can list their own addresses (req 15)', async () => {
  // A uid scoped to this one test — this suite's `customerAddresses`
  // fixtures otherwise reuse 'alice' across many tests within the same
  // emulator session (no per-test data reset), which would inflate this
  // count with unrelated docs seeded by other tests.
  const uid = 'list-test-carol';
  await seed(async (db) => {
    await setDoc(doc(db, 'customerAddresses/list-test-address-1'), { uid, label: 'Ev' });
    await setDoc(doc(db, 'customerAddresses/list-test-address-2'), { uid, label: 'İş' });
    await setDoc(doc(db, 'customerAddresses/list-test-address-other'), { uid: 'someone-else', label: 'Ev' });
  });
  const carol = testEnv.authenticatedContext(uid, {}).firestore();

  const snapshot = await getDocs(
    query(collection(carol, 'customerAddresses'), where('uid', '==', uid)),
  );
  assert.strictEqual(snapshot.size, 2);
});

test('customerAddresses: a direct client create is always denied, even under the caller\'s own uid — saveDeliveryAddress (Cloud Function) is the only path', async () => {
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertFails(
    setDoc(doc(alice, 'customerAddresses/address-spoof'), {
      uid: 'alice',
      label: 'Ev',
      verificationStatus: 'verified',
      verifiedAt: new Date().toISOString(),
    }),
  );
});

test('customerAddresses: owner metadata update (label/isDefault/apartmentNo/floor/addressDescription/buildingNoOverride) succeeds (req 16)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerAddresses/address-1'), {
      uid: 'alice',
      label: 'Ev',
      isDefault: false,
      apartmentNo: '4',
      verificationStatus: 'verified',
    });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertSucceeds(
    updateDoc(doc(alice, 'customerAddresses/address-1'), {
      label: 'İş',
      isDefault: true,
      apartmentNo: '5',
      floor: '3',
      addressDescription: 'Kapıcıya bırakın',
      buildingNoOverride: '12',
      updatedAt: new Date().toISOString(),
    }),
  );
});

test('customerAddresses: a client cannot self-mark an address verified via update — authoritative fields cannot be forged (req 13, 17)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerAddresses/address-1'), {
      uid: 'alice',
      label: 'Ev',
      verificationStatus: 'unverified',
      verifiedAt: null,
    });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertFails(
    updateDoc(doc(alice, 'customerAddresses/address-1'), {
      verificationStatus: 'verified',
      verifiedAt: new Date().toISOString(),
    }),
  );
});

test('customerAddresses: a client cannot forge provinceName/districtName/latitude/longitude/providerPlaceId via update (req 12, 17)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerAddresses/address-1'), {
      uid: 'alice',
      label: 'Ev',
      provinceName: 'İstanbul',
      districtName: 'Beşiktaş',
      latitude: 41.0,
      longitude: 29.0,
      providerPlaceId: 'real-place-id',
    });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertFails(
    updateDoc(doc(alice, 'customerAddresses/address-1'), {
      districtName: 'FAKE',
      latitude: 0,
      longitude: 0,
      providerPlaceId: 'forged-place-id',
    }),
  );
});

test('customerAddresses: a client cannot reassign uid via update (cross-owner takeover attempt)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerAddresses/address-1'), { uid: 'alice', label: 'Ev' });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertFails(
    updateDoc(doc(alice, 'customerAddresses/address-1'), { uid: 'bob', label: 'Ev' }),
  );
});

test('customerAddresses: a different customer cannot update or delete another\'s address (req 14)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerAddresses/address-1'), { uid: 'alice', label: 'Ev' });
  });
  const bob = testEnv.authenticatedContext('bob', {}).firestore();

  await assertFails(updateDoc(doc(bob, 'customerAddresses/address-1'), { label: 'İş' }));
  await assertFails(deleteDoc(doc(bob, 'customerAddresses/address-1')));
});

test('customerAddresses: owner can delete their own address', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerAddresses/address-1'), { uid: 'alice', label: 'Ev' });
  });
  const alice = testEnv.authenticatedContext('alice', {}).firestore();

  await assertSucceeds(deleteDoc(doc(alice, 'customerAddresses/address-1')));
});

// ---------------------------------------------------------------------
// Delivery Fraud Location Evidence — shared foundation (FRAUD-F.0,
// docs/decisions.md, docs/fraud_evidence_architecture.md).
//
// Every one of these four collections must deny direct human read/write
// for every role, with NO exception — not even platformOwner. Precise
// evidence access exists only through the `getPreciseFraudEvidence`
// Cloud Function, specifically because a Firestore Rule cannot itself
// produce the mandatory access-audit side effect that endpoint provides.
// This matrix proves that absence of a rules-based bypass for every role
// this app's authorization model recognizes, not just the "obvious" ones.
// ---------------------------------------------------------------------

const FRAUD_COLLECTIONS = [
  'fraudEvidence',
  'fraudRiskContexts',
  'fraudEvidenceAccessLog',
  'fraudEvidenceRetentionPolicies',
];

function fraudRoleContexts() {
  return {
    unauthenticated: () => testEnv.unauthenticatedContext(),
    customer: () => testEnv.authenticatedContext('fraud-customer', {}),
    courier: () =>
      testEnv.authenticatedContext('fraud-courier', {
        organizationAccess: ['org-1'],
        roles: { 'org-1': ['courier'] },
      }),
    staff: () =>
      testEnv.authenticatedContext('fraud-staff', {
        organizationAccess: ['org-1'],
        roles: { 'org-1': ['staff'] },
      }),
    manager: () =>
      testEnv.authenticatedContext('fraud-manager', {
        organizationAccess: ['org-1'],
        roles: { 'org-1': ['manager'] },
      }),
    admin: () =>
      testEnv.authenticatedContext('fraud-admin', {
        organizationAccess: ['org-1'],
        roles: { 'org-1': ['admin'] },
      }),
    unrelatedTenant: () =>
      testEnv.authenticatedContext('fraud-eve', {
        organizationAccess: ['org-2'],
        roles: { 'org-2': ['admin'] },
      }),
    platformAdministrator: () =>
      testEnv.authenticatedContext('fraud-platform-admin', {
        platformRole: 'platformAdministrator',
      }),
    platformOwner: () =>
      testEnv.authenticatedContext('fraud-platform-owner', {
        platformRole: 'platformOwner',
      }),
  };
}

for (const collectionName of FRAUD_COLLECTIONS) {
  const roleContexts = fraudRoleContexts();
  for (const [roleName, makeContext] of Object.entries(roleContexts)) {
    test(`${collectionName}: ${roleName} cannot read a seeded document directly`, async () => {
      const docId = `${collectionName}-read-${roleName}`;
      await seed(async (db) => {
        await setDoc(doc(db, `${collectionName}/${docId}`), { seeded: true });
      });
      const actor = makeContext().firestore();

      await assertFails(getDoc(doc(actor, `${collectionName}/${docId}`)));
    });

    test(`${collectionName}: ${roleName} cannot create a document directly`, async () => {
      const docId = `${collectionName}-create-${roleName}`;
      const actor = makeContext().firestore();

      await assertFails(
        setDoc(doc(actor, `${collectionName}/${docId}`), { forged: true }),
      );
    });

    test(`${collectionName}: ${roleName} cannot update a seeded document directly`, async () => {
      const docId = `${collectionName}-update-${roleName}`;
      await seed(async (db) => {
        await setDoc(doc(db, `${collectionName}/${docId}`), { seeded: true });
      });
      const actor = makeContext().firestore();

      await assertFails(
        updateDoc(doc(actor, `${collectionName}/${docId}`), { seeded: false }),
      );
    });

    test(`${collectionName}: ${roleName} cannot delete a seeded document directly`, async () => {
      const docId = `${collectionName}-delete-${roleName}`;
      await seed(async (db) => {
        await setDoc(doc(db, `${collectionName}/${docId}`), { seeded: true });
      });
      const actor = makeContext().firestore();

      await assertFails(deleteDoc(doc(actor, `${collectionName}/${docId}`)));
    });
  }
}

// ---------------------------------------------------------------------
// Delivery service areas (Paket Servis P.3) — same default-deny matrix,
// abbreviated (unlike the fraud collections, this is a single, low-
// sensitivity config collection with no admin UI yet — full 4-operation
// coverage per role would be redundant given the identical `if false`
// rule; a representative sample proves the boundary holds).
// ---------------------------------------------------------------------

test('deliveryServiceAreas: an unauthenticated caller cannot read a seeded area', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'deliveryServiceAreas/area-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      districtId: 'besiktas',
      neighborhoodId: 'levent',
      enabled: true,
      minimumOrderMinorUnits: 0,
    });
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'deliveryServiceAreas/area-1')));
});

test('deliveryServiceAreas: platformOwner cannot read a seeded area directly (no admin UI exists yet — Cloud Function/ops tooling only)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'deliveryServiceAreas/area-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      districtId: 'besiktas',
      neighborhoodId: 'levent',
      enabled: true,
      minimumOrderMinorUnits: 0,
    });
  });
  const owner = testEnv
    .authenticatedContext('platform-owner-1', { platformRole: 'platformOwner' })
    .firestore();

  await assertFails(getDoc(doc(owner, 'deliveryServiceAreas/area-1')));
});

test('deliveryServiceAreas: a customer cannot create a service-area document directly', async () => {
  const customer = testEnv.authenticatedContext('customer-1', {}).firestore();

  await assertFails(
    setDoc(doc(customer, 'deliveryServiceAreas/forged'), {
      districtId: 'besiktas',
      neighborhoodId: 'levent',
      enabled: true,
      minimumOrderMinorUnits: 0,
    }),
  );
});

// ---------------------------------------------------------------------
// Paket Servis P.3 — regression proof that direct customer creation of a
// `channel: 'delivery'` order remains denied now that submitDeliveryOrder
// exists as the sole authoritative creation path (Admin SDK, bypasses
// these Rules entirely). Mirrors the exact precedent already established
// for `channel: 'takeaway'` once submitTakeawayOrder became its sole
// creator (the removed isValidAuthenticatedTakeawayOrder branch) — no new
// `orders` create branch was added for delivery; this proves none is
// needed and none was silently left open.
// ---------------------------------------------------------------------

test('orders: an ordinary authenticated customer cannot directly create a channel:"delivery" order in Firestore — submitDeliveryOrder (Admin SDK) remains the only creation path', async () => {
  const customer = testEnv.authenticatedContext('customer-1', {}).firestore();

  await assertFails(
    setDoc(doc(customer, 'orders/forged-delivery-order'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'delivery',
      status: 'pendingConfirmation',
      customerId: 'customer-1',
    }),
  );
});

test('orders: staff (org member, no branch access) cannot create a channel:"delivery" order directly in Firestore', async () => {
  const staff = testEnv
    .authenticatedContext('staff-1', { organizationAccess: ['org-1'], roles: { 'org-1': ['staff'] } })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/forged-delivery-order-2'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'delivery',
      status: 'created',
      customerId: null,
    }),
  );
});

// Paket Servis P.3 — confirms the exclusion added to the `orders` create
// rule's staff branch is genuinely channel-based, not merely a side effect
// of the pre-existing (separate, untouched-by-this-phase) branch-access
// gap: even a staff actor WITH full branch access is still denied for
// channel:"delivery" specifically, while the identical write for a
// non-delivery channel (e.g. "dineInStaff") continues to succeed exactly
// as before — proving this phase did not weaken staff order creation for
// any other channel.
test('orders: staff WITH branch access still cannot create a channel:"delivery" order directly in Firestore — the exclusion is channel-based, not branch-based', async () => {
  const staff = testEnv
    .authenticatedContext('staff-2', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['staff'] },
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/forged-delivery-order-3'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'delivery',
      status: 'created',
      customerId: null,
    }),
  );

  await assertSucceeds(
    setDoc(doc(staff, 'orders/forged-non-delivery-order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'dineInStaff',
      status: 'created',
      customerId: null,
    }),
  );
});
