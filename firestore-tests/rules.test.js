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

// ---------------------------------------------------------------------
// AP-3 Wave 1 — Table Session + Guest Sub-Account (corrected Stage A
// report §1/§6/§8). Both are written exclusively by
// `openTableGuestSession`/`submitDineInOrder` (Admin SDK, bypasses these
// rules entirely) — these tests only cover what a *client* may do
// against an already-seeded document.
// ---------------------------------------------------------------------

// AP-3 Wave 1 SECURITY CORRECTION (2026-08-27) — the original Wave 1 rule
// granted staff read on `isOrgMember && hasBranchAccess` alone, which
// cannot verify AP-2's trusted-device session (a Rule has no way to
// re-derive the challenge-response proof `requireActiveDeviceSession`
// checks server-side). Corrected: NO staff read path exists in Rules at
// all for `tableSessions`/`guestSubAccounts`/`checks`/`checkAllocations`/
// `orderLineAllocationLedgers` — the sole staff read path is the new
// `getPosTableOperationalView` callable, tested separately against the
// Functions emulator (`functions/src/test/posOperationalView.test.ts`),
// not here (this file only exercises direct client Firestore access).

test('tableSessions: a branch-scoped staff member with full org+branch claims CANNOT read directly — membership/branch alone can never substitute for the trusted-device proof', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableSessions/ts-1'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      status: 'active',
    });
  });
  const branchStaff = testEnv
    .authenticatedContext('staff-branch', {
      organizationAccess: ['org-1'],
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();
  const orgOnlyStaff = testEnv
    .authenticatedContext('staff-org-only', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(getDoc(doc(branchStaff, 'tableSessions/ts-1')));
  await assertFails(getDoc(doc(orgOnlyStaff, 'tableSessions/ts-1')));
});

test('tableSessions: a different organization\'s staff member cannot read either — tenant isolation, doubly enforced (fails closed regardless) — same commit', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableSessions/ts-2'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      status: 'active',
    });
  });
  const otherOrgStaff = testEnv
    .authenticatedContext('staff-other-org', {
      organizationAccess: ['org-2'],
      branchAccess: { 'org-2': ['branch-1'] },
    })
    .firestore();

  await assertFails(getDoc(doc(otherOrgStaff, 'tableSessions/ts-2')));
});

test('tableSessions: no client (staff or guest) may ever write directly — Cloud Function (Admin SDK) only', async () => {
  const branchStaff = testEnv
    .authenticatedContext('staff-write', {
      organizationAccess: ['org-1'],
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();

  await assertFails(
    setDoc(doc(branchStaff, 'tableSessions/ts-3'), {
      organizationId: 'org-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      status: 'active',
    }),
  );
});

test('guestSubAccounts: the owner (matching ownerAuthUid) can read their own sub-account', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'guestSubAccounts/sub-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      tableSessionId: 'ts-1',
      ownerType: 'guestSession',
      ownerAuthUid: 'guest-uid-sub-1',
      displayName: 'Test Guest',
      status: 'open',
    });
  });
  const owner = testEnv.authenticatedContext('guest-uid-sub-1').firestore();

  await assertSucceeds(getDoc(doc(owner, 'guestSubAccounts/sub-1')));
});

test('guestSubAccounts: a DIFFERENT guest cannot read someone else\'s sub-account by knowing its id — IDOR protection, proves the fix is keyed on ownerAuthUid, not a session doc id', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'guestSubAccounts/sub-2'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      tableSessionId: 'ts-1',
      ownerType: 'guestSession',
      ownerAuthUid: 'guest-uid-sub-2',
      displayName: 'Test Guest',
      status: 'open',
    });
  });
  const attacker = testEnv.authenticatedContext('guest-uid-attacker-sub').firestore();

  await assertFails(getDoc(doc(attacker, 'guestSubAccounts/sub-2')));
});

test('guestSubAccounts: a staffGeneral/namedWalkIn sub-account with ownerAuthUid: null is never directly readable by ANYONE via Rules — no customer owns it, and staff has no direct Rules read path at all (getPosTableOperationalView only)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'guestSubAccounts/sub-3'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      tableSessionId: 'ts-1',
      ownerType: 'staffGeneral',
      ownerAuthUid: null,
      displayName: 'Masa Geneli',
      status: 'open',
    });
  });
  const randomCustomer = testEnv.authenticatedContext('some-customer').firestore();
  const branchStaff = testEnv
    .authenticatedContext('staff-branch-sub', {
      organizationAccess: ['org-1'],
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();

  await assertFails(getDoc(doc(randomCustomer, 'guestSubAccounts/sub-3')));
  await assertFails(getDoc(doc(branchStaff, 'guestSubAccounts/sub-3')));
});

test('guestSubAccounts: branch staff with full org+branch claims CANNOT read another guest\'s sub-account directly — the Wave 1 security correction, verified against a real guestSession-owned doc', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'guestSubAccounts/sub-4'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      tableSessionId: 'ts-1',
      ownerType: 'guestSession',
      ownerAuthUid: 'guest-uid-sub-4',
      displayName: 'Test Guest',
      status: 'open',
    });
  });
  const orgOnlyStaff = testEnv
    .authenticatedContext('staff-org-only-sub', { organizationAccess: ['org-1'] })
    .firestore();
  const branchStaff = testEnv
    .authenticatedContext('staff-branch-full-sub', {
      organizationAccess: ['org-1'],
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();

  await assertFails(getDoc(doc(orgOnlyStaff, 'guestSubAccounts/sub-4')));
  await assertFails(getDoc(doc(branchStaff, 'guestSubAccounts/sub-4')));
});

// ---------------------------------------------------------------------
// AP-3 Wave 2 — checks/checkAllocations/checkFinancialAdjustments/
// orderLineAllocationLedgers: no direct client read path at all, for
// anyone (staff or customer) — same fail-closed discipline as
// `tableSessions` above, `getPosTableOperationalView` is the sole staff
// read path, and no customer-facing UI reads any of these this phase.
// ---------------------------------------------------------------------

test('checks: no client — staff (even full org+branch claims) or customer — may read directly', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'checks/check-1'), {
      organizationId: 'org-1', branchId: 'branch-1', tableSessionId: 'ts-1',
      status: 'open', paymentActivityStarted: false, computedTotalMinorUnits: 0, currencyCode: 'TRY',
    });
  });
  const branchStaff = testEnv
    .authenticatedContext('staff-checks', { organizationAccess: ['org-1'], branchAccess: { 'org-1': ['branch-1'] } })
    .firestore();
  const customer = testEnv.authenticatedContext('some-customer-checks').firestore();

  await assertFails(getDoc(doc(branchStaff, 'checks/check-1')));
  await assertFails(getDoc(doc(customer, 'checks/check-1')));
});

test('checks: no client may ever write directly — Cloud Function (Admin SDK) only', async () => {
  const branchStaff = testEnv
    .authenticatedContext('staff-checks-write', { organizationAccess: ['org-1'], branchAccess: { 'org-1': ['branch-1'] } })
    .firestore();

  await assertFails(
    setDoc(doc(branchStaff, 'checks/check-2'), {
      organizationId: 'org-1', branchId: 'branch-1', tableSessionId: 'ts-1',
      status: 'open', paymentActivityStarted: false, computedTotalMinorUnits: 0, currencyCode: 'TRY',
    }),
  );
});

test('checkAllocations: no client may read or write directly, even full org+branch staff claims', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'checkAllocations/alloc-1'), {
      checkId: 'check-1', organizationId: 'org-1', branchId: 'branch-1', tableSessionId: 'ts-1',
      subAccountId: 'sub-1', splitMethod: 'product', sourceComposition: [], allocatedAmountMinorUnits: 1000,
      currencyCode: 'TRY', status: 'active',
    });
  });
  const branchStaff = testEnv
    .authenticatedContext('staff-alloc', { organizationAccess: ['org-1'], branchAccess: { 'org-1': ['branch-1'] } })
    .firestore();

  await assertFails(getDoc(doc(branchStaff, 'checkAllocations/alloc-1')));
  await assertFails(setDoc(doc(branchStaff, 'checkAllocations/alloc-2'), { checkId: 'check-1', status: 'active' }));
});

test('checkFinancialAdjustments: no client may read or write directly', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'checkFinancialAdjustments/adj-1'), {
      checkId: 'check-1', organizationId: 'org-1', branchId: 'branch-1', status: 'active',
    });
  });
  const branchStaff = testEnv
    .authenticatedContext('staff-adj', { organizationAccess: ['org-1'], branchAccess: { 'org-1': ['branch-1'] } })
    .firestore();

  await assertFails(getDoc(doc(branchStaff, 'checkFinancialAdjustments/adj-1')));
  await assertFails(setDoc(doc(branchStaff, 'checkFinancialAdjustments/adj-2'), { checkId: 'check-1', status: 'active' }));
});

test('orderLineAllocationLedgers: no client may read or write directly — internal accounting only', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orderLineAllocationLedgers/order-1_0'), {
      organizationId: 'org-1', branchId: 'branch-1', tableSessionId: 'ts-1',
      sourceOrderId: 'order-1', sourceLineIndex: 0, remainingQuantity: 1, remainingValueMinorUnits: 1000,
    });
  });
  const branchStaff = testEnv
    .authenticatedContext('staff-ledger', { organizationAccess: ['org-1'], branchAccess: { 'org-1': ['branch-1'] } })
    .firestore();

  await assertFails(getDoc(doc(branchStaff, 'orderLineAllocationLedgers/order-1_0')));
  await assertFails(setDoc(doc(branchStaff, 'orderLineAllocationLedgers/order-1_1'), { sourceOrderId: 'order-1' }));
});

test('guestSubAccounts: no client may ever write directly — Cloud Function (Admin SDK) only', async () => {
  const owner = testEnv.authenticatedContext('guest-uid-sub-write').firestore();

  await assertFails(
    setDoc(doc(owner, 'guestSubAccounts/sub-5'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      tableSessionId: 'ts-1',
      ownerType: 'guestSession',
      ownerAuthUid: 'guest-uid-sub-write',
      displayName: 'Test Guest',
      status: 'open',
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
// Table Guest Session order authorization (Phase 3) — originally the fix
// for the reported `orders/local-order-X PERMISSION_DENIED` bug via two
// direct-client-create rule branches (`isValidGuestTableOrder`/
// `isValidAuthenticatedCustomerTableOrder`).
//
// **Boncuk Loyalty P7-D.1 (2026-08-24) — both branches REMOVED.** Dine-in
// order creation (both an anonymous table guest and a real, phone-verified
// customer) is now exclusively server-authoritative via `submitDineInOrder`
// (Admin SDK, bypasses these rules entirely) — full canonical catalog/
// pricing/Loyalty validation no rules-only shape check could ever provide.
// Every "-> allow" test below that used to prove a direct client `create`
// succeeded now proves the OPPOSITE (`assertFails`) — the request shape
// itself is unchanged (still exactly what a legitimate order would have
// looked like), only the verdict flipped, since there is no longer ANY
// rule branch that could admit it. The already-`assertFails` tests in this
// section remain correctly denied, now for the same single reason (no
// client-create path exists for this channel at all) rather than each
// their own specific violation — still valid, still exercising real
// request shapes, no test removed. Read-ownership tests further below are
// completely unaffected (`read` was never touched by P7-D.1). The
// `isOrgMember` staff branch is never touched by any test in this
// section, deliberately preserved (POS/staff-assisted dine-in creation is
// out of P7-D.1's scope) — the pre-existing "an order can be created by an
// org member..." tests above already prove that branch still passes
// unchanged, for `dineInQr` included.
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

test('Boncuk Loyalty P7-D.1 (2026-08-24): anonymous + otherwise-valid table session/customerId/guestAuthUid shape -> now DENIED — isValidGuestTableOrder was removed; submitDineInOrder is the sole create path', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-1'),
      activeGuestSession({ guestAuthUid: 'guest-uid-1' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-uid-1').firestore();

  await assertFails(
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

test('Boncuk Loyalty P7-D.1 (2026-08-24): real customer + otherwise-valid session/customerId shape -> now DENIED — isValidAuthenticatedCustomerTableOrder was removed; submitDineInOrder is the sole create path', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-20'),
      activeGuestSession({ guestAuthUid: 'customer-uid-1' }),
    );
  });
  const customer = customerContext('customer-uid-1');

  await assertFails(
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

test('Boncuk Loyalty P7-D.1 (2026-08-24): reservation-context session + matching order reservationContextId -> now DENIED — direct client create removed entirely; submitDineInOrder re-derives and re-checks this server-side', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-1'),
      activeGuestSession({ guestAuthUid: 'guest-uid-rc-1', reservationContextId: 'RES_123' }),
    );
    await setDoc(doc(db, 'reservations/RES_123'), reservationPayload({ status: 'confirmed' }));
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-1').firestore();

  await assertFails(
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

test('Boncuk Loyalty P7-D.1 (2026-08-24): reservation-context session, real phone-verified customer variant, exact match -> now DENIED', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-rc-6'),
      activeGuestSession({ guestAuthUid: 'customer-uid-rc-6', reservationContextId: 'RES_CUSTOMER' }),
    );
    await setDoc(doc(db, 'reservations/RES_CUSTOMER'), reservationPayload({ status: 'confirmed' }));
  });
  const customer = customerContext('customer-uid-rc-6');

  await assertFails(
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

test('Boncuk Loyalty P7-D.1 (2026-08-24): ordinary walk-in dine-in order (no reservationContextId at all) direct client create -> now DENIED, same as every other create variant in this section', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tableGuestSessions/tgs-rc-11'), activeGuestSession({ guestAuthUid: 'guest-uid-rc-11' }));
  });
  const guest = testEnv.authenticatedContext('guest-uid-rc-11').firestore();

  await assertFails(
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

// =====================================================================
// Customer Registration CR.1 (2026-08-19) — tenantCustomers is Cloud-
// Function-only (`allow write: if false`), and the new registration-form
// PII fields on customers/{uid} must stay off the client update
// allow-list. Neither was previously covered by a dedicated test — the
// audit's own report named this exact gap.
// =====================================================================

test('CR.1: a customer cannot directly create their own tenantCustomers membership document', async () => {
  const dave = testEnv.authenticatedContext('dave', {}).firestore();

  await assertFails(
    setDoc(doc(dave, 'tenantCustomers/org-1_dave'), {
      organizationId: 'org-1',
      uid: 'dave',
    }),
  );
});

test('CR.1: a customer cannot update an existing tenantCustomers membership document either — write is unconditionally denied, not just create', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tenantCustomers/org-1_erin'), {
      organizationId: 'org-1',
      uid: 'erin',
    });
  });
  const erin = testEnv.authenticatedContext('erin', {}).firestore();

  await assertFails(
    updateDoc(doc(erin, 'tenantCustomers/org-1_erin'), { visitCount: 999 }),
  );
});

test('CR.1: a customer cannot delete their own tenantCustomers membership document', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tenantCustomers/org-1_frank'), {
      organizationId: 'org-1',
      uid: 'frank',
    });
  });
  const frank = testEnv.authenticatedContext('frank', {}).firestore();

  await assertFails(deleteDoc(doc(frank, 'tenantCustomers/org-1_frank')));
});

test('CR.1: a customer cannot forge the new registration fields (gender/occupationStatus/etc.) via the client update path — only displayName/email stay allow-listed', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customers/grace'), {
      displayName: 'Grace',
      email: 'grace@example.com',
      firstName: 'Grace',
      lastName: 'Hopper',
      occupationStatus: 'other',
      gender: 'female',
    });
  });
  const grace = testEnv.authenticatedContext('grace', {}).firestore();

  // Even alongside an otherwise-allowed field, ANY additional key outside
  // the allow-list fails the whole update — an allow-list, not a partial
  // best-effort filter.
  await assertFails(
    updateDoc(doc(grace, 'customers/grace'), {
      displayName: 'Grace Updated',
      gender: 'male',
    }),
  );
  await assertFails(
    updateDoc(doc(grace, 'customers/grace'), { occupationStatus: 'working' }),
  );
  await assertFails(
    updateDoc(doc(grace, 'customers/grace'), { firstName: 'Forged' }),
  );
  // The pre-existing allow-listed fields remain genuinely updatable —
  // proves the fix didn't accidentally tighten the rule beyond what CR.1
  // asked for.
  await assertSucceeds(
    updateDoc(doc(grace, 'customers/grace'), { displayName: 'Grace Updated' }),
  );
});

test('CR.1.1: a customer cannot directly set or change birthDate via the client update path — it stays off the allow-list, first-write or otherwise', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customers/hank'), {
      displayName: 'Hank',
      email: 'hank@example.com',
      birthDate: '1990-08-20',
    });
  });
  const hank = testEnv.authenticatedContext('hank', {}).firestore();

  await assertFails(
    updateDoc(doc(hank, 'customers/hank'), { birthDate: '2001-01-01' }),
  );
  await assertFails(
    updateDoc(doc(hank, 'customers/hank'), {
      displayName: 'Hank Updated',
      birthDate: '2001-01-01',
    }),
  );
  // Existing allow-listed fields remain genuinely updatable — the
  // birthDate exclusion doesn't regress the rest of the allow-list.
  await assertSucceeds(
    updateDoc(doc(hank, 'customers/hank'), { displayName: 'Hank Updated' }),
  );
});

test('a platform member without an active support grant cannot read tenant data outside their own scope (restaurants/branches/staffMembers — everything still gated by canReadOrg alone)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'restaurants/restaurant-1'), { organizationId: 'org-1', name: 'Merkez' });
  });
  const platformAdmin = testEnv
    .authenticatedContext('platform-1', { platformRole: 'platformAdministrator' })
    .firestore();

  await assertFails(getDoc(doc(platformAdmin, 'restaurants/restaurant-1')));
});

test('a platform member WITH an active, non-expired support grant can read that tenant\'s data', async () => {
  const future = new Date(Date.now() + 60 * 60 * 1000);
  await seed(async (db) => {
    await setDoc(doc(db, 'restaurants/restaurant-1'), { organizationId: 'org-1', name: 'Merkez' });
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

  await assertSucceeds(getDoc(doc(platformAdmin, 'restaurants/restaurant-1')));
});

test('an EXPIRED support grant no longer grants access — time-limited, not permanent', async () => {
  const past = new Date(Date.now() - 60 * 60 * 1000);
  await seed(async (db) => {
    await setDoc(doc(db, 'restaurants/restaurant-1'), { organizationId: 'org-1', name: 'Merkez' });
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

  await assertFails(getDoc(doc(platformAdmin, 'restaurants/restaurant-1')));
});

test('AP-2 final wiring — organizations (narrow exception, tenant-picker need): any platform member can read directly, no support grant required; a tenant staff member never gains cross-org read from this', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'organizations/org-1'), { name: 'Abaküs' });
  });
  const platformAdmin = testEnv
    .authenticatedContext('platform-1', { platformRole: 'platformAdministrator' })
    .firestore();
  const platformOwner = testEnv
    .authenticatedContext('platform-2', { platformRole: 'platformOwner' })
    .firestore();
  const outsiderStaff = testEnv
    .authenticatedContext('staff-9', { organizationAccess: ['org-2'], roles: { 'org-2': ['admin'] } })
    .firestore();

  await assertSucceeds(getDoc(doc(platformAdmin, 'organizations/org-1')));
  await assertSucceeds(getDoc(doc(platformOwner, 'organizations/org-1')));
  await assertFails(getDoc(doc(outsiderStaff, 'organizations/org-1')));
  await assertFails(setDoc(doc(platformAdmin, 'organizations/org-1'), { name: 'Hijacked' }));
});

test('AP-2 final wiring — entitlements: a platform member can read any tenant\'s entitlement docs directly (needed to render the grant/renew/suspend/revoke console before acting), but still cannot write any of them client-side', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'entitlements/org-1_organization_org-1_pos'), {
      organizationId: 'org-1', scopeType: 'organization', scopeId: 'org-1', module: 'pos', status: 'active', version: 1,
    });
  });
  const platformOwner = testEnv
    .authenticatedContext('platform-1', { platformRole: 'platformOwner' })
    .firestore();
  const outsiderStaff = testEnv
    .authenticatedContext('staff-9', { organizationAccess: ['org-2'], roles: { 'org-2': ['admin'] } })
    .firestore();

  await assertSucceeds(getDoc(doc(platformOwner, 'entitlements/org-1_organization_org-1_pos')));
  await assertFails(getDoc(doc(outsiderStaff, 'entitlements/org-1_organization_org-1_pos')));
  await assertFails(
    setDoc(doc(platformOwner, 'entitlements/org-1_organization_org-1_pos'), { status: 'revoked' }),
  );
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

// ---------------------------------------------------------------------
// Boncuk Loyalty P2A security fix (2026-08-21) — `pricingAuthority` is a
// server-only marker of trusted pricing provenance, distinct from
// `channel`. No client create path, on any channel, for any actor, may
// ever supply this field — only `submitTakeawayOrder`/`submitDeliveryOrder`/
// `reservationPreorder` (Admin SDK, bypasses these rules) ever write it.
// ---------------------------------------------------------------------

test('pricingAuthority: a legitimate existing staff/POS dine-in order WITHOUT the marker remains allowed exactly as before this fix', async () => {
  const staff = testEnv
    .authenticatedContext('staff-pa-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(
    setDoc(doc(staff, 'orders/pa-legit-staff-order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'dineInStaff',
      status: 'created',
      customerId: null,
    }),
  );
});

test('Boncuk Loyalty P7-D.1 (2026-08-24): pricingAuthority — a guest table (dineInQr) order create is now DENIED regardless of the marker, since the direct-client guest-create path was removed entirely; the sibling staff/POS positive control above already proves this rule does not over-block a still-legitimate client create', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-pa-1'),
      activeGuestSession({ guestAuthUid: 'guest-pa-1' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-pa-1').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/pa-legit-guest-order-1'),
      tableOrderPayload({ tableSessionId: 'tgs-pa-1', guestAuthUid: 'guest-pa-1' }),
    ),
  );
});

test('pricingAuthority: a malicious org-member client cannot forge channel:"takeaway" + pricingAuthority:"serverV1" — DENIED', async () => {
  const staff = testEnv
    .authenticatedContext('staff-pa-2', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/pa-forged-takeaway-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'takeaway',
      status: 'created',
      customerId: null,
      pricingAuthority: 'serverV1',
    }),
  );
});

test('pricingAuthority: a malicious org-member client cannot forge channel:"reservationPreorder" + pricingAuthority:"serverV1" — DENIED', async () => {
  const staff = testEnv
    .authenticatedContext('staff-pa-3', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/pa-forged-preorder-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'reservationPreorder',
      status: 'created',
      customerId: null,
      pricingAuthority: 'serverV1',
    }),
  );
});

test('pricingAuthority: an org-member client cannot forge it even on a channel that is not itself eligible for earning (defense in depth — the rule forbids the field unconditionally, not just on eligible channels)', async () => {
  const staff = testEnv
    .authenticatedContext('staff-pa-4', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/pa-forged-dineinstaff-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'dineInStaff',
      status: 'created',
      customerId: null,
      pricingAuthority: 'serverV1',
    }),
  );
});

test('pricingAuthority: a guest/customer table order cannot inject the marker — DENIED even though the rest of the payload is otherwise a valid guest table order', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-pa-2'),
      activeGuestSession({ guestAuthUid: 'guest-pa-2' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-pa-2').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/pa-forged-guest-order-1'),
      tableOrderPayload({
        tableSessionId: 'tgs-pa-2',
        guestAuthUid: 'guest-pa-2',
        pricingAuthority: 'serverV1',
      }),
    ),
  );
});

test('pricingAuthority: an authenticated customer table order cannot inject the marker — DENIED', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-pa-3'),
      activeGuestSession({ guestAuthUid: 'cust-pa-3' }),
    );
  });
  const customer = customerContext('cust-pa-3');

  await assertFails(
    setDoc(
      doc(customer, 'orders/pa-forged-customer-order-1'),
      tableOrderPayload({
        tableSessionId: 'tgs-pa-3',
        guestAuthUid: 'cust-pa-3',
        customerId: 'cust-pa-3',
        pricingAuthority: 'serverV1',
      }),
    ),
  );
});

test('pricingAuthority: client updates remain denied regardless of this fix — a staff actor cannot add the marker to an existing order via update either', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/pa-existing-order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'takeaway',
      status: 'pendingConfirmation',
      customerId: null,
    });
  });
  const staff = testEnv
    .authenticatedContext('staff-pa-5', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    updateDoc(doc(staff, 'orders/pa-existing-order-1'), {
      pricingAuthority: 'serverV1',
    }),
  );
});

// ---------------------------------------------------------------------
// Boncuk Loyalty P4-B (2026-08-22) — `boncukRedemption` and
// `selectedBenefitType: 'boncukRedemption'` are settlement facts computed
// exclusively inside `submitTakeawayOrder.ts`'s own server-authoritative
// transaction. Exactly like `pricingAuthority` above, no client create
// path — staff/POS, an anonymous QR guest, or a real-customer QR guest —
// may ever claim a Boncuk redemption for itself, on any channel.
// ---------------------------------------------------------------------

test('boncukRedemption: a legitimate existing staff/POS dine-in order WITHOUT the fields remains allowed', async () => {
  const staff = testEnv
    .authenticatedContext('staff-br-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(
    setDoc(doc(staff, 'orders/br-legit-staff-order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'dineInStaff',
      status: 'created',
      customerId: null,
    }),
  );
});

test('Boncuk Loyalty P7-D.1 (2026-08-24): boncukRedemption — a guest table (dineInQr) order create is now DENIED regardless of the fields, since the direct-client guest-create path was removed entirely; the sibling staff/POS positive control above already proves this rule does not over-block a still-legitimate client create', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-br-1'),
      activeGuestSession({ guestAuthUid: 'guest-br-1' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-br-1').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/br-legit-guest-order-1'),
      tableOrderPayload({ tableSessionId: 'tgs-br-1', guestAuthUid: 'guest-br-1' }),
    ),
  );
});

test('boncukRedemption: explicitly setting selectedBenefitType:"none" remains allowed — the rule forbids the redemption value, not the discriminator field itself', async () => {
  const staff = testEnv
    .authenticatedContext('staff-br-none', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(
    setDoc(doc(staff, 'orders/br-legit-staff-order-none'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'takeaway',
      status: 'created',
      customerId: null,
      selectedBenefitType: 'none',
    }),
  );
});

test('boncukRedemption: a malicious org-member client cannot forge a boncukRedemption block on channel:"takeaway" — DENIED', async () => {
  const staff = testEnv
    .authenticatedContext('staff-br-2', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/br-forged-takeaway-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'takeaway',
      status: 'created',
      customerId: null,
      selectedBenefitType: 'boncukRedemption',
      boncukRedemption: {
        boncukUsed: 100,
        valueMinorUnits: 10000,
        remainingPayableMinorUnits: 0,
        redemptionValueMinorUnitsPerBoncuk: 100,
        maxRedemptionBasisPoints: 5000,
        loyaltyPolicyVersion: 1,
      },
    }),
  );
});

test('boncukRedemption: an org-member client cannot forge it even on a channel this phase never wires it to (defense in depth — the rule forbids the fields unconditionally)', async () => {
  const staff = testEnv
    .authenticatedContext('staff-br-3', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/br-forged-dineinstaff-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'dineInStaff',
      status: 'created',
      customerId: null,
      boncukRedemption: {
        boncukUsed: 1,
        valueMinorUnits: 100,
        remainingPayableMinorUnits: 0,
        redemptionValueMinorUnitsPerBoncuk: 100,
        maxRedemptionBasisPoints: 5000,
        loyaltyPolicyVersion: 1,
      },
    }),
  );
});

test('boncukRedemption: an org-member client cannot claim the benefit type alone, even without a boncukRedemption block — DENIED', async () => {
  const staff = testEnv
    .authenticatedContext('staff-br-4', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/br-forged-benefit-type-only-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'takeaway',
      status: 'created',
      customerId: null,
      selectedBenefitType: 'boncukRedemption',
    }),
  );
});

test('boncukRedemption: an anonymous guest table order cannot inject the fields — DENIED even though the rest of the payload is otherwise a valid guest table order', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-br-2'),
      activeGuestSession({ guestAuthUid: 'guest-br-2' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-br-2').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/br-forged-guest-order-1'),
      tableOrderPayload({
        tableSessionId: 'tgs-br-2',
        guestAuthUid: 'guest-br-2',
        boncukRedemption: {
          boncukUsed: 1,
          valueMinorUnits: 100,
          remainingPayableMinorUnits: 0,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
          loyaltyPolicyVersion: 1,
        },
      }),
    ),
  );
});

test('boncukRedemption: an authenticated customer table order cannot inject the fields — DENIED', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-br-3'),
      activeGuestSession({ guestAuthUid: 'cust-br-3' }),
    );
  });
  const customer = customerContext('cust-br-3');

  await assertFails(
    setDoc(
      doc(customer, 'orders/br-forged-customer-order-1'),
      tableOrderPayload({
        tableSessionId: 'tgs-br-3',
        guestAuthUid: 'cust-br-3',
        customerId: 'cust-br-3',
        selectedBenefitType: 'boncukRedemption',
        boncukRedemption: {
          boncukUsed: 1,
          valueMinorUnits: 100,
          remainingPayableMinorUnits: 0,
          redemptionValueMinorUnitsPerBoncuk: 100,
          maxRedemptionBasisPoints: 5000,
          loyaltyPolicyVersion: 1,
        },
      }),
    ),
  );
});

test('boncukRedemption: client updates remain denied regardless of this fix — a staff actor cannot add the fields to an existing order via update either', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/br-existing-order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'takeaway',
      status: 'pendingConfirmation',
      customerId: null,
    });
  });
  const staff = testEnv
    .authenticatedContext('staff-br-5', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    updateDoc(doc(staff, 'orders/br-existing-order-1'), {
      selectedBenefitType: 'boncukRedemption',
      boncukRedemption: {
        boncukUsed: 1,
        valueMinorUnits: 100,
        remainingPayableMinorUnits: 0,
        redemptionValueMinorUnitsPerBoncuk: 100,
        maxRedemptionBasisPoints: 5000,
        loyaltyPolicyVersion: 1,
      },
    }),
  );
});

// ---------------------------------------------------------------------
// Boncuk Loyalty P7-D (2026-08-24) — `catalogReward` and
// `selectedBenefitType: 'catalogReward'` are the identical class of
// server-authoritative-only fact `boncukRedemption` already was — this
// section is the catalogReward sibling of the boncukRedemption forgery
// tests immediately above, specifically closing the gap the P7-D dine-in
// audit found: dine-in (`dineInQr`) order CREATION has no server pipeline
// at all, so a client-forged `catalogReward` snapshot must be blocked
// outright by rules, not merely "nothing legitimate can produce it yet."
// ---------------------------------------------------------------------

const forgedCatalogReward = {
  rewardId: 'reward-1',
  rewardVersion: 1,
  title: 'Test Reward',
  boncukCost: 1,
  redeemedProductId: 'prod-1',
  redeemedQuantity: 1,
  coveredValueMinorUnits: 100,
  rewardCatalogVersionId: 'reward-1_1',
  orderChannel: 'dineIn',
};

test('catalogReward: a malicious org-member client cannot forge a catalogReward block on channel:"takeaway" — DENIED', async () => {
  const staff = testEnv
    .authenticatedContext('staff-cr-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/cr-forged-takeaway-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'takeaway',
      status: 'created',
      customerId: null,
      selectedBenefitType: 'catalogReward',
      catalogReward: forgedCatalogReward,
    }),
  );
});

test('catalogReward: an org-member client cannot forge it on dineInStaff either — defense in depth, the rule forbids the fields unconditionally', async () => {
  const staff = testEnv
    .authenticatedContext('staff-cr-2', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/cr-forged-dineinstaff-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'dineInStaff',
      status: 'created',
      customerId: null,
      catalogReward: forgedCatalogReward,
    }),
  );
});

test('catalogReward: an org-member client cannot claim the benefit type alone, even without a catalogReward block — DENIED', async () => {
  const staff = testEnv
    .authenticatedContext('staff-cr-3', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(staff, 'orders/cr-forged-benefit-type-only-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'takeaway',
      status: 'created',
      customerId: null,
      selectedBenefitType: 'catalogReward',
    }),
  );
});

test('catalogReward: an anonymous guest table (dineInQr) order cannot inject a forged catalogReward — DENIED, closing the exact gap the P7-D dine-in audit found (no server pipeline exists yet to produce a real one)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-cr-1'),
      activeGuestSession({ guestAuthUid: 'guest-cr-1' }),
    );
  });
  const guest = testEnv.authenticatedContext('guest-cr-1').firestore();

  await assertFails(
    setDoc(
      doc(guest, 'orders/cr-forged-guest-order-1'),
      tableOrderPayload({
        tableSessionId: 'tgs-cr-1',
        guestAuthUid: 'guest-cr-1',
        selectedBenefitType: 'catalogReward',
        catalogReward: forgedCatalogReward,
      }),
    ),
  );
});

test('catalogReward: an authenticated customer table order cannot inject a forged catalogReward — DENIED (a real phone-verified dine-in customer still has no legitimate way to redeem one today)', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'tableGuestSessions/tgs-cr-2'),
      activeGuestSession({ guestAuthUid: 'cust-cr-2' }),
    );
  });
  const customer = customerContext('cust-cr-2');

  await assertFails(
    setDoc(
      doc(customer, 'orders/cr-forged-customer-order-1'),
      tableOrderPayload({
        tableSessionId: 'tgs-cr-2',
        guestAuthUid: 'cust-cr-2',
        customerId: 'cust-cr-2',
        selectedBenefitType: 'catalogReward',
        catalogReward: forgedCatalogReward,
      }),
    ),
  );
});

test('catalogReward: client updates remain denied regardless of this fix — a staff actor cannot add the fields to an existing order via update either', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'orders/cr-existing-order-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
      channel: 'takeaway',
      status: 'pendingConfirmation',
      customerId: null,
    });
  });
  const staff = testEnv
    .authenticatedContext('staff-cr-4', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    updateDoc(doc(staff, 'orders/cr-existing-order-1'), {
      selectedBenefitType: 'catalogReward',
      catalogReward: forgedCatalogReward,
    }),
  );
});

// ---------------------------------------------------------------------
// P.4.1 — Profile photo architecture prep: customerPhotos,
// customerPublicProfiles, and customers/{uid}.profilePicturePath
// client-write tightening.
// ---------------------------------------------------------------------

test('customers: a client can no longer directly set profilePicturePath — selection must be server-authoritative (P.4.1)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customers/photo-owner-1'), {
      displayName: 'Photo Owner',
      email: 'owner@example.com',
    });
  });
  const owner = testEnv.authenticatedContext('photo-owner-1', {}).firestore();

  await assertFails(
    updateDoc(doc(owner, 'customers/photo-owner-1'), {
      profilePicturePath: 'tenants/org-1/customerPhotos/photo-owner-1/spoofed.jpg',
    }),
  );
  // displayName/email remain client-updatable — the tightening is scoped
  // to profilePicturePath only, not a regression of the whole allow-list.
  await assertSucceeds(
    updateDoc(doc(owner, 'customers/photo-owner-1'), {
      displayName: 'Photo Owner Updated',
    }),
  );
});

test('customerPhotos: the owning customer can read their own private gallery entry', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotos/photo-1'), {
      customerId: 'photo-owner-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/photo-owner-1/a.jpg',
      status: 'pendingReview',
    });
  });
  const owner = testEnv.authenticatedContext('photo-owner-1', {}).firestore();

  await assertSucceeds(getDoc(doc(owner, 'customerPhotos/photo-1')));
});

test('customerPhotos: a different customer cannot read another customer\'s gallery entry', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotos/photo-1'), {
      customerId: 'photo-owner-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/photo-owner-1/a.jpg',
      status: 'pendingReview',
    });
  });
  const otherCustomer = testEnv.authenticatedContext('photo-intruder-1', {}).firestore();

  await assertFails(getDoc(doc(otherCustomer, 'customerPhotos/photo-1')));
});

test('customerPhotos: a customer belonging to a different tenant cannot read the gallery entry', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotos/photo-1'), {
      customerId: 'photo-owner-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/photo-owner-1/a.jpg',
      status: 'pendingReview',
    });
    // A real tenantCustomers record for a DIFFERENT org — proves this
    // isn't denied merely for lacking any tenantCustomers doc at all, but
    // specifically for belonging to the wrong tenant.
    await setDoc(doc(db, 'tenantCustomers/org-2_photo-intruder-1'), {
      organizationId: 'org-2',
    });
  });
  const crossTenantCustomer = testEnv.authenticatedContext('photo-intruder-1', {}).firestore();

  await assertFails(getDoc(doc(crossTenantCustomer, 'customerPhotos/photo-1')));
});

test('customerPhotos: authorized same-org staff can read a customer\'s gallery entry', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotos/photo-1'), {
      customerId: 'photo-owner-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/photo-owner-1/a.jpg',
      status: 'pendingReview',
    });
  });
  const staff = testEnv
    .authenticatedContext('staff-photo-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(getDoc(doc(staff, 'customerPhotos/photo-1')));
});

test('customerPhotos: staff from a different organization cannot read the gallery entry', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotos/photo-1'), {
      customerId: 'photo-owner-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/photo-owner-1/a.jpg',
      status: 'pendingReview',
    });
  });
  const otherOrgStaff = testEnv
    .authenticatedContext('staff-photo-other-org', { organizationAccess: ['org-2'] })
    .firestore();

  await assertFails(getDoc(doc(otherOrgStaff, 'customerPhotos/photo-1')));
});

test('customerPhotos: an unauthenticated caller cannot read a gallery entry', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotos/photo-1'), {
      customerId: 'photo-owner-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/photo-owner-1/a.jpg',
      status: 'pendingReview',
    });
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'customerPhotos/photo-1')));
});

test('customerPhotos: every direct client write is denied — create, update, and delete, even by the owner or same-org staff', async () => {
  const owner = testEnv.authenticatedContext('photo-owner-1', {}).firestore();
  const staff = testEnv
    .authenticatedContext('staff-photo-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(owner, 'customerPhotos/photo-spoof-1'), {
      customerId: 'photo-owner-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/photo-owner-1/spoof.jpg',
      status: 'approved',
      isSelectedAsProfilePhoto: true,
    }),
  );

  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotos/photo-2'), {
      customerId: 'photo-owner-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/photo-owner-1/b.jpg',
      status: 'pendingReview',
    });
  });

  // Neither the owner nor staff can forge/self-approve a status change —
  // "status/selected/reviewer fields cannot be forged by client" holds
  // because there is no client write path at all, not a restricted one.
  await assertFails(
    updateDoc(doc(owner, 'customerPhotos/photo-2'), { status: 'approved' }),
  );
  await assertFails(
    updateDoc(doc(staff, 'customerPhotos/photo-2'), {
      status: 'approved',
      isSelectedAsProfilePhoto: true,
    }),
  );
  await assertFails(deleteDoc(doc(owner, 'customerPhotos/photo-2')));
  await assertFails(deleteDoc(doc(staff, 'customerPhotos/photo-2')));
});

test('CR.1.2: the onboarding-intent (purpose) field introduces no new client-write bypass — a client cannot create or forge it either', async () => {
  const owner = testEnv.authenticatedContext('photo-owner-1', {}).firestore();

  // Cannot create a fresh doc carrying a purpose field — same
  // Cloud-Function-only rule as every other field on this collection.
  await assertFails(
    setDoc(doc(owner, 'customerPhotos/photo-onboarding-spoof'), {
      customerId: 'photo-owner-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/photo-owner-1/spoof.jpg',
      status: 'pendingReview',
      purpose: 'profileOnboarding',
    }),
  );

  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotos/photo-3'), {
      customerId: 'photo-owner-1',
      organizationId: 'org-1',
      photoRef: 'tenants/org-1/customerPhotos/photo-owner-1/c.jpg',
      status: 'pendingReview',
      purpose: null,
    });
  });

  // Cannot retroactively claim onboarding intent on an existing photo the
  // client never declared it for — the field stays Cloud-Function-only,
  // never a client-writable one, matching every other CR.1.2 field.
  await assertFails(
    updateDoc(doc(owner, 'customerPhotos/photo-3'), { purpose: 'profileOnboarding' }),
  );
});

test('customerPublicProfiles: same-org staff can read the public projection', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPublicProfiles/org-1_photo-owner-1'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      selectedProfilePhotoRef: null,
    });
  });
  const staff = testEnv
    .authenticatedContext('staff-photo-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertSucceeds(
    getDoc(doc(staff, 'customerPublicProfiles/org-1_photo-owner-1')),
  );
});

test('customerPublicProfiles: an authenticated same-tenant customer can read the public projection', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPublicProfiles/org-1_photo-owner-1'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      selectedProfilePhotoRef: null,
    });
    await setDoc(doc(db, 'tenantCustomers/org-1_photo-viewer-1'), {
      organizationId: 'org-1',
    });
  });
  const sameTenantCustomer = testEnv.authenticatedContext('photo-viewer-1', {}).firestore();

  await assertSucceeds(
    getDoc(doc(sameTenantCustomer, 'customerPublicProfiles/org-1_photo-owner-1')),
  );
});

test('customerPublicProfiles: a guest/unauthenticated caller cannot read the public projection', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPublicProfiles/org-1_photo-owner-1'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      selectedProfilePhotoRef: null,
    });
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(
    getDoc(doc(anon, 'customerPublicProfiles/org-1_photo-owner-1')),
  );
});

test('customerPublicProfiles: a cross-tenant customer (no tenantCustomers record for this org) cannot read the public projection', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPublicProfiles/org-1_photo-owner-1'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      selectedProfilePhotoRef: null,
    });
    await setDoc(doc(db, 'tenantCustomers/org-2_photo-viewer-2'), {
      organizationId: 'org-2',
    });
  });
  const crossTenantCustomer = testEnv.authenticatedContext('photo-viewer-2', {}).firestore();

  await assertFails(
    getDoc(doc(crossTenantCustomer, 'customerPublicProfiles/org-1_photo-owner-1')),
  );
});

test('customerPublicProfiles: staff from a different organization cannot read the public projection', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPublicProfiles/org-1_photo-owner-1'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      selectedProfilePhotoRef: null,
    });
  });
  const otherOrgStaff = testEnv
    .authenticatedContext('staff-photo-other-org', { organizationAccess: ['org-2'] })
    .firestore();

  await assertFails(
    getDoc(doc(otherOrgStaff, 'customerPublicProfiles/org-1_photo-owner-1')),
  );
});

test('customerPublicProfiles: no client — not the owner, not staff — can write the public projection directly', async () => {
  const owner = testEnv.authenticatedContext('photo-owner-1', {}).firestore();
  const staff = testEnv
    .authenticatedContext('staff-photo-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(
    setDoc(doc(owner, 'customerPublicProfiles/org-1_photo-owner-1'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      selectedProfilePhotoRef: 'tenants/org-1/customerPhotos/photo-owner-1/spoof.jpg',
    }),
  );

  await seed(async (db) => {
    await setDoc(doc(db, 'customerPublicProfiles/org-1_photo-owner-2'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      selectedProfilePhotoRef: null,
    });
  });
  await assertFails(
    updateDoc(doc(owner, 'customerPublicProfiles/org-1_photo-owner-2'), {
      selectedProfilePhotoRef: 'tenants/org-1/customerPhotos/photo-owner-1/spoof.jpg',
    }),
  );
  await assertFails(
    updateDoc(doc(staff, 'customerPublicProfiles/org-1_photo-owner-2'), {
      selectedProfilePhotoRef: 'tenants/org-1/customerPhotos/photo-owner-1/spoof.jpg',
    }),
  );
});

// ---------------------------------------------------------------------
// P.4.2A — customerPhotoUploadGrants: deny-all from the client SDK.
// (storage.rules' own cross-service firestore.get() read of this
// collection is exercised by storage-tests/rules.test.js, not here —
// this suite only proves no ordinary Firestore client can read/write it.)
// ---------------------------------------------------------------------

test('customerPhotoUploadGrants: the owning customer cannot read their own grant directly — the callable already returns everything the client needs', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotoUploadGrants/grant-1'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      objectPath: 'tenants/org-1/customerPhotos/photo-owner-1/grant-1',
      contentType: 'image/png',
      status: 'issued',
    });
  });
  const owner = testEnv.authenticatedContext('photo-owner-1', {}).firestore();

  await assertFails(getDoc(doc(owner, 'customerPhotoUploadGrants/grant-1')));
});

test('customerPhotoUploadGrants: same-org staff cannot read a grant directly either', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotoUploadGrants/grant-2'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      objectPath: 'tenants/org-1/customerPhotos/photo-owner-1/grant-2',
      contentType: 'image/png',
      status: 'issued',
    });
  });
  const staff = testEnv
    .authenticatedContext('staff-photo-1', { organizationAccess: ['org-1'] })
    .firestore();

  await assertFails(getDoc(doc(staff, 'customerPhotoUploadGrants/grant-2')));
});

test('customerPhotoUploadGrants: no client — not even the intended owner — can write a grant directly (create, update, or delete)', async () => {
  const owner = testEnv.authenticatedContext('photo-owner-1', {}).firestore();

  await assertFails(
    setDoc(doc(owner, 'customerPhotoUploadGrants/grant-spoof'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      objectPath: 'tenants/org-1/customerPhotos/photo-owner-1/grant-spoof',
      contentType: 'image/png',
      status: 'issued',
    }),
  );

  await seed(async (db) => {
    await setDoc(doc(db, 'customerPhotoUploadGrants/grant-3'), {
      uid: 'photo-owner-1',
      organizationId: 'org-1',
      objectPath: 'tenants/org-1/customerPhotos/photo-owner-1/grant-3',
      contentType: 'image/png',
      status: 'issued',
    });
  });
  await assertFails(
    updateDoc(doc(owner, 'customerPhotoUploadGrants/grant-3'), { status: 'consumed' }),
  );
  await assertFails(deleteDoc(doc(owner, 'customerPhotoUploadGrants/grant-3')));
});

// =========================================================================
// Boncuk Loyalty Program (P1, 2026-08-20) — loyaltyAccounts / loyaltyLedgerEntries
//
// **Tenant isolation security fix (same day)**: `customerId ==
// request.auth.uid` alone is NOT sufficient tenant authorization — a
// Firebase Auth uid is global, so the same uid could (once real
// multi-tenant customer membership exists) legitimately have a loyalty
// record in more than one organization. Every test below that seeds a
// document the caller is expected to successfully read now ALSO seeds a
// genuine `tenantCustomers/{organizationId}_{uid}` membership document for
// that exact organizationId — omitting it (or seeding one for the wrong
// org) is now the mandatory failure mode this suite proves.
// =========================================================================

function loyaltyAccountFixture(overrides = {}) {
  return {
    organizationId: 'org-1',
    customerId: 'loyalty-owner-1',
    spendableBalance: 0,
    earningRemainderMinorUnits: 0,
    lifetimeEarned: 0,
    lifetimeRedeemed: 0,
    revision: 1,
    ...overrides,
  };
}

function loyaltyLedgerEntryFixture(overrides = {}) {
  return {
    organizationId: 'org-1',
    customerId: 'loyalty-owner-1',
    entryType: 'orderEarn',
    deltaBoncuk: 5,
    createdAt: Timestamp.now(),
    ...overrides,
  };
}

async function seedMembership(db, uid, organizationId) {
  await setDoc(doc(db, `tenantCustomers/${organizationId}_${uid}`), { organizationId, uid });
}

test('loyaltyAccounts: same uid + valid membership in org-A -> reading the org-A account succeeds', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyAccounts/org-1_loyalty-owner-1'), loyaltyAccountFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
  });
  const owner = customerContext('loyalty-owner-1');

  await assertSucceeds(getDoc(doc(owner, 'loyaltyAccounts/org-1_loyalty-owner-1')));
});

test('loyaltyAccounts: same uid but NO membership at all for org-B -> reading the org-B account is denied', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'loyaltyAccounts/org-2_loyalty-owner-2'),
      loyaltyAccountFixture({ organizationId: 'org-2', customerId: 'loyalty-owner-2' }),
    );
    // Deliberately no tenantCustomers/org-2_loyalty-owner-2 seeded at all.
  });
  const owner = customerContext('loyalty-owner-2');

  await assertFails(getDoc(doc(owner, 'loyaltyAccounts/org-2_loyalty-owner-2')));
});

test('loyaltyAccounts: same uid with genuine membership in org-A cannot exploit customerId equality to read an org-B account under that same uid — the mandatory same-uid/wrong-tenant case', async () => {
  const uid = 'loyalty-owner-3';
  await seed(async (db) => {
    await setDoc(
      doc(db, 'loyaltyAccounts/org-2_loyalty-owner-3'),
      loyaltyAccountFixture({ organizationId: 'org-2', customerId: uid }),
    );
    // Real membership exists, but only for org-1 — never for org-2, the
    // organization the target document actually belongs to.
    await seedMembership(db, uid, 'org-1');
  });
  const caller = customerContext(uid);

  await assertFails(getDoc(doc(caller, 'loyaltyAccounts/org-2_loyalty-owner-3')));
});

test('loyaltyAccounts: a different customer (different uid) is denied even with their own valid membership', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyAccounts/org-1_loyalty-owner-1'), loyaltyAccountFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
    await seedMembership(db, 'loyalty-intruder-1', 'org-1');
  });
  const otherCustomer = customerContext('loyalty-intruder-1');

  await assertFails(getDoc(doc(otherCustomer, 'loyaltyAccounts/org-1_loyalty-owner-1')));
});

test('loyaltyAccounts: a guest/anonymous technical identity cannot read an account, even their own uid\'s with a real membership doc present', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'loyaltyAccounts/org-1_guest-uid-1'),
      loyaltyAccountFixture({ customerId: 'guest-uid-1' }),
    );
    await seedMembership(db, 'guest-uid-1', 'org-1');
  });
  // A real anonymous Firebase Auth session (isSignedIn() true, but
  // isRealCustomerAuth() false) — distinct from testEnv.unauthenticatedContext(),
  // which has no request.auth at all. Mirrors this file's own established
  // sign_in_provider simulation convention (see customerContext above).
  const guest = testEnv
    .authenticatedContext('guest-uid-1', { firebase: { sign_in_provider: 'anonymous' } })
    .firestore();

  await assertFails(getDoc(doc(guest, 'loyaltyAccounts/org-1_guest-uid-1')));
});

test('loyaltyAccounts: an unauthenticated caller cannot read an account', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyAccounts/org-1_loyalty-owner-1'), loyaltyAccountFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'loyaltyAccounts/org-1_loyalty-owner-1')));
});

test('loyaltyAccounts: no client — not even the owner with valid membership — can create, update, or delete an account directly', async () => {
  const owner = customerContext('loyalty-owner-1');

  await assertFails(setDoc(doc(owner, 'loyaltyAccounts/org-1_loyalty-owner-1'), loyaltyAccountFixture({ spendableBalance: 999999 })));

  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyAccounts/org-1_loyalty-owner-1'), loyaltyAccountFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
  });
  await assertFails(
    updateDoc(doc(owner, 'loyaltyAccounts/org-1_loyalty-owner-1'), { spendableBalance: 999999 }),
  );
  await assertFails(deleteDoc(doc(owner, 'loyaltyAccounts/org-1_loyalty-owner-1')));
});

test('loyaltyLedgerEntries: same uid + org-A membership -> reading the own org-A entry succeeds', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyLedgerEntries/entry-1'), loyaltyLedgerEntryFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
  });
  const owner = customerContext('loyalty-owner-1');

  await assertSucceeds(getDoc(doc(owner, 'loyaltyLedgerEntries/entry-1')));
});

test('loyaltyLedgerEntries: same uid but no membership for org-B -> reading the org-B entry is denied', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'loyaltyLedgerEntries/entry-org-b-1'),
      loyaltyLedgerEntryFixture({ organizationId: 'org-2', customerId: 'loyalty-owner-2' }),
    );
    // Deliberately no tenantCustomers/org-2_loyalty-owner-2 seeded.
  });
  const owner = customerContext('loyalty-owner-2');

  await assertFails(getDoc(doc(owner, 'loyaltyLedgerEntries/entry-org-b-1')));
});

test('loyaltyLedgerEntries: same uid with genuine membership in org-A cannot read an org-B entry under that same uid', async () => {
  const uid = 'loyalty-owner-3';
  await seed(async (db) => {
    await setDoc(
      doc(db, 'loyaltyLedgerEntries/entry-org-b-2'),
      loyaltyLedgerEntryFixture({ organizationId: 'org-2', customerId: uid }),
    );
    await seedMembership(db, uid, 'org-1');
  });
  const caller = customerContext(uid);

  await assertFails(getDoc(doc(caller, 'loyaltyLedgerEntries/entry-org-b-2')));
});

test('loyaltyLedgerEntries: a different customer cannot read another customer\'s entry, even with their own valid membership', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyLedgerEntries/entry-1'), loyaltyLedgerEntryFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
    await seedMembership(db, 'loyalty-intruder-1', 'org-1');
  });
  const otherCustomer = customerContext('loyalty-intruder-1');

  await assertFails(getDoc(doc(otherCustomer, 'loyaltyLedgerEntries/entry-1')));
});

test('loyaltyLedgerEntries: a guest/anonymous technical identity cannot read an entry, even one seeded under their own uid with a real membership doc present', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'loyaltyLedgerEntries/entry-guest-1'),
      loyaltyLedgerEntryFixture({ customerId: 'guest-uid-2' }),
    );
    await seedMembership(db, 'guest-uid-2', 'org-1');
  });
  const guest = testEnv
    .authenticatedContext('guest-uid-2', { firebase: { sign_in_provider: 'anonymous' } })
    .firestore();

  await assertFails(getDoc(doc(guest, 'loyaltyLedgerEntries/entry-guest-1')));
});

test('loyaltyLedgerEntries: no client can create, update, or delete an entry directly', async () => {
  const owner = customerContext('loyalty-owner-1');

  await assertFails(
    setDoc(doc(owner, 'loyaltyLedgerEntries/entry-spoof'), loyaltyLedgerEntryFixture({ deltaBoncuk: 999999 })),
  );

  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyLedgerEntries/entry-1'), loyaltyLedgerEntryFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
  });
  await assertFails(
    updateDoc(doc(owner, 'loyaltyLedgerEntries/entry-1'), { deltaBoncuk: 999999 }),
  );
  await assertFails(deleteDoc(doc(owner, 'loyaltyLedgerEntries/entry-1')));
});

test('loyaltyLedgerEntries: history query for org-A + own uid + own valid org-A membership succeeds and returns only the owner\'s own entries', async () => {
  const uid = 'loyalty-history-owner-1';
  await seed(async (db) => {
    await setDoc(doc(db, `loyaltyLedgerEntries/${uid}-entry-1`), loyaltyLedgerEntryFixture({ customerId: uid }));
    await setDoc(
      doc(db, `loyaltyLedgerEntries/${uid}-entry-2`),
      loyaltyLedgerEntryFixture({ customerId: uid, deltaBoncuk: 3 }),
    );
    await setDoc(
      doc(db, 'loyaltyLedgerEntries/unrelated-entry-1'),
      loyaltyLedgerEntryFixture({ customerId: 'someone-else', deltaBoncuk: 10 }),
    );
    await seedMembership(db, uid, 'org-1');
  });
  const owner = customerContext(uid);

  const snapshot = await getDocs(
    query(
      collection(owner, 'loyaltyLedgerEntries'),
      where('customerId', '==', uid),
      where('organizationId', '==', 'org-1'),
    ),
  );
  assert.strictEqual(snapshot.size, 2);
});

test('loyaltyLedgerEntries: a history query scoped to org-B with the caller\'s own uid is denied when the caller has no org-B membership — the mandatory same-uid/wrong-tenant query case', async () => {
  const uid = 'loyalty-history-owner-2';
  await seed(async (db) => {
    await setDoc(
      doc(db, `loyaltyLedgerEntries/${uid}-org-b-entry-1`),
      loyaltyLedgerEntryFixture({ organizationId: 'org-2', customerId: uid }),
    );
    // Membership only for org-1 — the query below targets org-2.
    await seedMembership(db, uid, 'org-1');
  });
  const caller = customerContext(uid);

  await assertFails(
    getDocs(
      query(
        collection(caller, 'loyaltyLedgerEntries'),
        where('customerId', '==', uid),
        where('organizationId', '==', 'org-2'),
      ),
    ),
  );
});

test('loyaltyLedgerEntries: a query that omits the required organizationId scope is denied outright, not silently filtered', async () => {
  const uid = 'loyalty-scope-owner-1';
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyLedgerEntries/scope-test-entry-1'), loyaltyLedgerEntryFixture({ customerId: uid }));
    await seedMembership(db, uid, 'org-1');
  });
  const caller = customerContext(uid);

  await assertFails(
    getDocs(query(collection(caller, 'loyaltyLedgerEntries'), where('customerId', '==', uid))),
  );
});

test('loyaltyLedgerEntries: a query that omits the required customerId scope is denied outright, not silently filtered', async () => {
  const uid = 'loyalty-scope-owner-3';
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyLedgerEntries/scope-test-entry-3'), loyaltyLedgerEntryFixture({ customerId: uid }));
    await seedMembership(db, uid, 'org-1');
  });
  const caller = customerContext(uid);

  await assertFails(
    getDocs(query(collection(caller, 'loyaltyLedgerEntries'), where('organizationId', '==', 'org-1'))),
  );
});

test('loyaltyLedgerEntries: a query targeting another customer\'s uid is denied, even when the caller only ever asks for their own valid tenant', async () => {
  const targetUid = 'loyalty-scope-owner-2';
  await seed(async (db) => {
    await setDoc(
      doc(db, 'loyaltyLedgerEntries/other-uid-entry-1'),
      loyaltyLedgerEntryFixture({ customerId: targetUid }),
    );
    await seedMembership(db, targetUid, 'org-1');
    await seedMembership(db, 'loyalty-intruder-2', 'org-1');
  });
  const caller = customerContext('loyalty-intruder-2');

  await assertFails(
    getDocs(
      query(
        collection(caller, 'loyaltyLedgerEntries'),
        where('customerId', '==', targetUid),
        where('organizationId', '==', 'org-1'),
      ),
    ),
  );
});

// =========================================================================
// Reward Catalog — Boncuk Loyalty Program P7-B (2026-08-24).
// loyaltyRewardCatalog / loyaltyRewardCatalogVersions. No client, not even
// the reward's own organization's member, ever reads either collection
// directly — `getCustomerLoyaltyRewardCatalog` (Cloud Function) is the sole
// read path. Unconditional `allow read, write: if false` for both.
// =========================================================================

function loyaltyRewardCatalogFixture(overrides = {}) {
  return {
    rewardId: 'icecek',
    organizationId: 'org-1',
    title: 'İçecek',
    description: 'Test.',
    rewardType: 'explicitProductSet',
    eligibleProductIds: ['prod_cocacola'],
    boncukCost: 70,
    active: true,
    archived: false,
    sortOrder: 0,
    version: 1,
    validFrom: null,
    validUntil: null,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...overrides,
  };
}

test('loyaltyRewardCatalog: a real, tenant-member customer cannot read a reward document directly', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyRewardCatalog/icecek'), loyaltyRewardCatalogFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
  });
  const owner = customerContext('loyalty-owner-1');

  await assertFails(getDoc(doc(owner, 'loyaltyRewardCatalog/icecek')));
});

test('loyaltyRewardCatalog: an unauthenticated caller cannot read a reward document', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyRewardCatalog/icecek'), loyaltyRewardCatalogFixture());
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'loyaltyRewardCatalog/icecek')));
});

test('loyaltyRewardCatalog: a list query is denied outright, for any authenticated identity', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyRewardCatalog/icecek'), loyaltyRewardCatalogFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
  });
  const owner = customerContext('loyalty-owner-1');

  await assertFails(
    getDocs(query(collection(owner, 'loyaltyRewardCatalog'), where('organizationId', '==', 'org-1'))),
  );
});

test('loyaltyRewardCatalog: no client can create, update, or delete a reward document directly', async () => {
  const owner = customerContext('loyalty-owner-1');
  await assertFails(setDoc(doc(owner, 'loyaltyRewardCatalog/icecek'), loyaltyRewardCatalogFixture()));

  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyRewardCatalog/icecek'), loyaltyRewardCatalogFixture());
  });
  await assertFails(updateDoc(doc(owner, 'loyaltyRewardCatalog/icecek'), { boncukCost: 999999 }));
  await assertFails(deleteDoc(doc(owner, 'loyaltyRewardCatalog/icecek')));
});

function loyaltyRewardCatalogVersionFixture(overrides = {}) {
  return {
    rewardId: 'icecek',
    organizationId: 'org-1',
    title: 'İçecek',
    description: 'Test.',
    rewardType: 'explicitProductSet',
    eligibleProductIds: ['prod_cocacola'],
    boncukCost: 70,
    sortOrder: 0,
    version: 1,
    validFrom: null,
    validUntil: null,
    effectiveAt: Timestamp.now(),
    createdAt: Timestamp.now(),
    ...overrides,
  };
}

test('loyaltyRewardCatalogVersions: a real, tenant-member customer cannot read a version document directly', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyRewardCatalogVersions/icecek_1'), loyaltyRewardCatalogVersionFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
  });
  const owner = customerContext('loyalty-owner-1');

  await assertFails(getDoc(doc(owner, 'loyaltyRewardCatalogVersions/icecek_1')));
});

test('loyaltyRewardCatalogVersions: a list query is denied outright', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyRewardCatalogVersions/icecek_1'), loyaltyRewardCatalogVersionFixture());
    await seedMembership(db, 'loyalty-owner-1', 'org-1');
  });
  const owner = customerContext('loyalty-owner-1');

  await assertFails(
    getDocs(query(collection(owner, 'loyaltyRewardCatalogVersions'), where('rewardId', '==', 'icecek'))),
  );
});

test('loyaltyRewardCatalogVersions: no client can create, update, or delete a version document directly', async () => {
  const owner = customerContext('loyalty-owner-1');
  await assertFails(
    setDoc(doc(owner, 'loyaltyRewardCatalogVersions/icecek_1'), loyaltyRewardCatalogVersionFixture()),
  );

  await seed(async (db) => {
    await setDoc(doc(db, 'loyaltyRewardCatalogVersions/icecek_1'), loyaltyRewardCatalogVersionFixture());
  });
  await assertFails(
    updateDoc(doc(owner, 'loyaltyRewardCatalogVersions/icecek_1'), { boncukCost: 999999 }),
  );
  await assertFails(deleteDoc(doc(owner, 'loyaltyRewardCatalogVersions/icecek_1')));
});

// =========================================================================
// Campaigns — Server-Authoritative Campaign Engine P8-B (2026-08-25).
// campaigns / campaignVersions / campaignUsageCounters /
// campaignCustomerUsage / campaignUsageReservations. Mirrors the Reward
// Catalog section immediately above, exactly — no client, not even a
// tenant-member customer, ever reads or writes any of these five
// collections directly. Unconditional `allow read, write: if false` for
// all five.
// =========================================================================

function campaignFixture(overrides = {}) {
  return {
    campaignId: 'hafta-ici-ogle',
    organizationId: 'org-1',
    title: 'Hafta İçi Öğle',
    description: 'Test.',
    campaignType: 'percentageDiscount',
    rule: { mechanic: 'percentage', percentBasisPoints: 1500, scope: { kind: 'order' } },
    eligibleChannels: ['dineIn', 'takeaway'],
    eligibleProductIds: null,
    eligibleCategoryIds: null,
    minimumBasketMinorUnits: null,
    schedule: { mode: 'oneTime', startAt: null, endAt: null },
    usageLimit: null,
    perCustomerUsageLimit: null,
    active: true,
    archived: false,
    sortOrder: 0,
    version: 1,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...overrides,
  };
}

test('campaigns: a real, tenant-member customer cannot read a campaign document directly', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'campaigns/hafta-ici-ogle'), campaignFixture());
    await seedMembership(db, 'campaign-owner-1', 'org-1');
  });
  const owner = customerContext('campaign-owner-1');

  await assertFails(getDoc(doc(owner, 'campaigns/hafta-ici-ogle')));
});

test('campaigns: an unauthenticated caller cannot read a campaign document', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'campaigns/hafta-ici-ogle'), campaignFixture());
  });
  const anon = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(anon, 'campaigns/hafta-ici-ogle')));
});

test('campaigns: a list query is denied outright, for any authenticated identity', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'campaigns/hafta-ici-ogle'), campaignFixture());
    await seedMembership(db, 'campaign-owner-1', 'org-1');
  });
  const owner = customerContext('campaign-owner-1');

  await assertFails(
    getDocs(query(collection(owner, 'campaigns'), where('organizationId', '==', 'org-1'))),
  );
});

test('campaigns: no client can create, update, or delete a campaign document directly', async () => {
  const owner = customerContext('campaign-owner-1');
  await assertFails(setDoc(doc(owner, 'campaigns/hafta-ici-ogle'), campaignFixture()));

  await seed(async (db) => {
    await setDoc(doc(db, 'campaigns/hafta-ici-ogle'), campaignFixture());
  });
  await assertFails(updateDoc(doc(owner, 'campaigns/hafta-ici-ogle'), { active: false }));
  await assertFails(deleteDoc(doc(owner, 'campaigns/hafta-ici-ogle')));
});

test('campaignVersions: no client can read, create, update, or delete a version document directly', async () => {
  const versionFixture = { ...campaignFixture(), effectiveAt: Timestamp.now() };
  const owner = customerContext('campaign-owner-1');
  await assertFails(setDoc(doc(owner, 'campaignVersions/hafta-ici-ogle_1'), versionFixture));

  await seed(async (db) => {
    await setDoc(doc(db, 'campaignVersions/hafta-ici-ogle_1'), versionFixture);
    await seedMembership(db, 'campaign-owner-1', 'org-1');
  });
  await assertFails(getDoc(doc(owner, 'campaignVersions/hafta-ici-ogle_1')));
  await assertFails(updateDoc(doc(owner, 'campaignVersions/hafta-ici-ogle_1'), { title: 'Forged' }));
  await assertFails(deleteDoc(doc(owner, 'campaignVersions/hafta-ici-ogle_1')));
});

test('campaignUsageCounters: no client can read or write a usage counter directly — never client authority over usage count', async () => {
  const counterFixture = { organizationId: 'org-1', campaignId: 'hafta-ici-ogle', usageCount: 0 };
  const owner = customerContext('campaign-owner-1');
  await assertFails(
    setDoc(doc(owner, 'campaignUsageCounters/org-1_hafta-ici-ogle'), counterFixture),
  );

  await seed(async (db) => {
    await setDoc(doc(db, 'campaignUsageCounters/org-1_hafta-ici-ogle'), counterFixture);
  });
  await assertFails(getDoc(doc(owner, 'campaignUsageCounters/org-1_hafta-ici-ogle')));
  await assertFails(
    updateDoc(doc(owner, 'campaignUsageCounters/org-1_hafta-ici-ogle'), { usageCount: 999999 }),
  );
});

test('campaignCustomerUsage: no client can read or write their own per-customer usage record directly', async () => {
  const usageFixture = {
    organizationId: 'org-1',
    campaignId: 'hafta-ici-ogle',
    customerId: 'campaign-owner-1',
    usageCount: 0,
  };
  const owner = customerContext('campaign-owner-1');
  await assertFails(
    setDoc(doc(owner, 'campaignCustomerUsage/org-1_hafta-ici-ogle_campaign-owner-1'), usageFixture),
  );

  await seed(async (db) => {
    await setDoc(doc(db, 'campaignCustomerUsage/org-1_hafta-ici-ogle_campaign-owner-1'), usageFixture);
  });
  await assertFails(getDoc(doc(owner, 'campaignCustomerUsage/org-1_hafta-ici-ogle_campaign-owner-1')));
});

test('campaignUsageReservations: no client can read or write a usage reservation directly', async () => {
  const reservationFixture = {
    organizationId: 'org-1',
    campaignId: 'hafta-ici-ogle',
    customerId: null,
    orderId: 'order-1',
    status: 'reserved',
    reservedAt: Timestamp.now(),
    releasedAt: null,
  };
  const owner = customerContext('campaign-owner-1');
  await assertFails(
    setDoc(doc(owner, 'campaignUsageReservations/org-1_hafta-ici-ogle_order-1'), reservationFixture),
  );

  await seed(async (db) => {
    await setDoc(doc(db, 'campaignUsageReservations/org-1_hafta-ici-ogle_order-1'), reservationFixture);
  });
  await assertFails(getDoc(doc(owner, 'campaignUsageReservations/org-1_hafta-ici-ogle_order-1')));
});

// ===========================================================================
// AP-2 Stage B — Trusted Device / Remote Approval / Platform Bootstrap rules
// ===========================================================================

test('platformBootstrapMarkers: readable by a platform member, never by tenant staff, never client-writable', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'platformBootstrapMarkers/run-1'), {
      runId: 'run-1',
      uids: ['owner-uid-1'],
      role: 'platformOwner',
      executedAt: Timestamp.now(),
    });
  });
  const platformOwner = testEnv
    .authenticatedContext('platform-1', { platformRole: 'platformOwner' })
    .firestore();
  const tenantOwner = testEnv
    .authenticatedContext('owner-1', { organizationAccess: ['org-1'], roles: { 'org-1': ['tenantOwner'] } })
    .firestore();

  await assertSucceeds(getDoc(doc(platformOwner, 'platformBootstrapMarkers/run-1')));
  await assertFails(getDoc(doc(tenantOwner, 'platformBootstrapMarkers/run-1')));
  await assertFails(setDoc(doc(platformOwner, 'platformBootstrapMarkers/run-2'), { runId: 'run-2' }));
});

test('trustedDeviceRegistrations: readable only by staff with real org membership AND branch access for that exact branch; never client-writable', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'trustedDeviceRegistrations/org-1_branch-1_device-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      deviceId: 'device-1',
      status: 'active',
    });
  });
  const branchStaff = testEnv
    .authenticatedContext('staff-1', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['staff'] },
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();
  const orgOnlyNoAccess = testEnv
    .authenticatedContext('staff-2', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['staff'] },
      branchAccess: { 'org-1': ['branch-2'] },
    })
    .firestore();
  const outsider = testEnv
    .authenticatedContext('staff-3', {
      organizationAccess: ['org-2'],
      roles: { 'org-2': ['admin'] },
      branchAccess: { 'org-2': ['branch-9'] },
    })
    .firestore();

  await assertSucceeds(getDoc(doc(branchStaff, 'trustedDeviceRegistrations/org-1_branch-1_device-1')));
  await assertFails(getDoc(doc(orgOnlyNoAccess, 'trustedDeviceRegistrations/org-1_branch-1_device-1')));
  await assertFails(getDoc(doc(outsider, 'trustedDeviceRegistrations/org-1_branch-1_device-1')));
  await assertFails(
    setDoc(doc(branchStaff, 'trustedDeviceRegistrations/org-1_branch-1_device-2'), {
      organizationId: 'org-1', branchId: 'branch-1', deviceId: 'device-2', status: 'pending',
    }),
  );
});

test('deviceChallenges and deviceSessions: no client read or write at all, for anyone, at any permission level', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'deviceChallenges/challenge-1'), { deviceId: 'device-1', nonce: 'abc' });
    await setDoc(doc(db, 'deviceSessions/session-1'), { deviceId: 'device-1', status: 'active' });
  });
  const platformOwner = testEnv
    .authenticatedContext('platform-1', { platformRole: 'platformOwner' })
    .firestore();
  const branchStaff = testEnv
    .authenticatedContext('staff-1', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['admin'] },
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();

  for (const ctx of [platformOwner, branchStaff]) {
    await assertFails(getDoc(doc(ctx, 'deviceChallenges/challenge-1')));
    await assertFails(getDoc(doc(ctx, 'deviceSessions/session-1')));
  }
  await assertFails(setDoc(doc(branchStaff, 'deviceChallenges/challenge-2'), { deviceId: 'x' }));
  await assertFails(setDoc(doc(branchStaff, 'deviceSessions/session-2'), { deviceId: 'x' }));
});

test('remoteApprovalRequests: AP-2 final wiring — readable by the requester themselves, and by a branch-scoped eligible responder (manager/admin/tenantOwner); never by an unrelated org member, an org member without branch access, or an org-admin without branch access; never client-writable', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'remoteApprovalRequests/approval-1'), {
      organizationId: 'org-1',
      branchId: 'branch-1',
      actionType: 'deviceActivation',
      requestedByActorUid: 'staff-1',
      status: 'pending',
    });
  });
  const requester = testEnv
    .authenticatedContext('staff-1', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['staff'] },
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();
  // A different staff member on the SAME branch — not the requester, and
  // "staff" is not in RESPONSE_PERMISSION_BY_ACTION's role set — must stay denied.
  const uninvolvedBranchStaff = testEnv
    .authenticatedContext('staff-2', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['staff'] },
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();
  const eligibleManager = testEnv
    .authenticatedContext('manager-1', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['manager'] },
      branchAccess: { 'org-1': ['branch-1'] },
    })
    .firestore();
  // Admin role, but not granted access to THIS branch — must stay denied
  // (branch scope is required in addition to the response-permission role).
  const adminWrongBranch = testEnv
    .authenticatedContext('admin-1', {
      organizationAccess: ['org-1'],
      roles: { 'org-1': ['admin'] },
      branchAccess: { 'org-1': ['branch-2'] },
    })
    .firestore();
  const outsider = testEnv
    .authenticatedContext('staff-3', {
      organizationAccess: ['org-2'],
      roles: { 'org-2': ['admin'] },
      branchAccess: { 'org-2': ['branch-9'] },
    })
    .firestore();

  await assertSucceeds(getDoc(doc(requester, 'remoteApprovalRequests/approval-1')));
  await assertSucceeds(getDoc(doc(eligibleManager, 'remoteApprovalRequests/approval-1')));
  await assertFails(getDoc(doc(uninvolvedBranchStaff, 'remoteApprovalRequests/approval-1')));
  await assertFails(getDoc(doc(adminWrongBranch, 'remoteApprovalRequests/approval-1')));
  await assertFails(getDoc(doc(outsider, 'remoteApprovalRequests/approval-1')));
  await assertFails(setDoc(doc(eligibleManager, 'remoteApprovalRequests/approval-2'), { status: 'pending' }));
});

test('approvalEvents: readable by any real org member (minimum-data audit history), never client-writable', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'approvalEvents/event-1'), {
      requestId: 'approval-1',
      organizationId: 'org-1',
      branchId: 'branch-1',
      eventType: 'approval.approved',
    });
  });
  const orgMember = testEnv
    .authenticatedContext('staff-1', { organizationAccess: ['org-1'], roles: { 'org-1': ['staff'] } })
    .firestore();
  const outsider = testEnv
    .authenticatedContext('staff-2', { organizationAccess: ['org-2'], roles: { 'org-2': ['admin'] } })
    .firestore();

  await assertSucceeds(getDoc(doc(orgMember, 'approvalEvents/event-1')));
  await assertFails(getDoc(doc(outsider, 'approvalEvents/event-1')));
  await assertFails(setDoc(doc(orgMember, 'approvalEvents/event-2'), { requestId: 'x' }));
});

test('notificationOutbox: never end-user readable or writable, for anyone', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'notificationOutbox/entry-1'), { organizationId: 'org-1', type: 'approval.escalationNeeded' });
  });
  const platformOwner = testEnv
    .authenticatedContext('platform-1', { platformRole: 'platformOwner' })
    .firestore();
  const orgAdmin = testEnv
    .authenticatedContext('admin-1', { organizationAccess: ['org-1'], roles: { 'org-1': ['admin'] } })
    .firestore();

  await assertFails(getDoc(doc(platformOwner, 'notificationOutbox/entry-1')));
  await assertFails(getDoc(doc(orgAdmin, 'notificationOutbox/entry-1')));
});

// ---------------------------------------------------------------------
// AP-3 Wave 3 — Customer Directory (corrected report §4/§5/§7). Every
// projection/restriction collection is callable-only, no direct client
// read at all, for ANY actor including a Platform Owner or a full-claims
// org admin — the read APIs (`customerDirectory.ts`) are the sole path.
// ---------------------------------------------------------------------

test('platformCustomerDirectoryEntries: no direct client read, not even by a Platform Owner or a tenant admin', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'platformCustomerDirectoryEntries/uid-1'), {
      uid: 'uid-1', displayName: 'Test Customer', phoneNumber: '+15551234567', phoneSearchHash: 'abc',
      registrationDate: new Date(), accountState: 'active',
    });
  });
  const platformOwner = testEnv.authenticatedContext('platform-directory-1', { platformRole: 'platformOwner' }).firestore();
  const orgAdmin = testEnv.authenticatedContext('admin-directory-1', { organizationAccess: ['org-1'], roles: { 'org-1': ['admin'] } }).firestore();

  await assertFails(getDoc(doc(platformOwner, 'platformCustomerDirectoryEntries/uid-1')));
  await assertFails(getDoc(doc(orgAdmin, 'platformCustomerDirectoryEntries/uid-1')));
  await assertFails(setDoc(doc(platformOwner, 'platformCustomerDirectoryEntries/uid-2'), { uid: 'uid-2' }));
});

test('customerDirectoryEntries: no direct client read, not even by full org+branch staff claims', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'customerDirectoryEntries/org-1_uid-1'), {
      organizationId: 'org-1', customerId: 'uid-1', displayName: 'Test Customer', phoneNumber: '+15551234567', phoneSearchHash: 'abc',
      registrationDate: new Date(), lastActivityAt: new Date(), accountState: 'active', relatedBranchIds: ['branch-1'], lastOrderAt: null, totalOrderCount: 0,
    });
  });
  const branchStaff = testEnv.authenticatedContext('staff-directory-1', { organizationAccess: ['org-1'], branchAccess: { 'org-1': ['branch-1'] } }).firestore();

  await assertFails(getDoc(doc(branchStaff, 'customerDirectoryEntries/org-1_uid-1')));
  await assertFails(setDoc(doc(branchStaff, 'customerDirectoryEntries/org-1_uid-2'), { organizationId: 'org-1' }));
});

test('tenantCustomerRestrictions / platformCustomerRestrictions: no direct client read or write for anyone', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'tenantCustomerRestrictions/org-1_uid-1'), { organizationId: 'org-1', customerId: 'uid-1', status: 'active' });
    await setDoc(doc(db, 'platformCustomerRestrictions/uid-1'), { uid: 'uid-1', status: 'active' });
  });
  const manager = testEnv.authenticatedContext('manager-restriction-1', { organizationAccess: ['org-1'], roles: { 'org-1': ['manager'] } }).firestore();
  const platformOwner = testEnv.authenticatedContext('platform-restriction-1', { platformRole: 'platformOwner' }).firestore();

  await assertFails(getDoc(doc(manager, 'tenantCustomerRestrictions/org-1_uid-1')));
  await assertFails(getDoc(doc(platformOwner, 'platformCustomerRestrictions/uid-1')));
  await assertFails(setDoc(doc(manager, 'tenantCustomerRestrictions/org-1_uid-2'), { organizationId: 'org-1' }));
  await assertFails(setDoc(doc(platformOwner, 'platformCustomerRestrictions/uid-2'), { uid: 'uid-2' }));
});
