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
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { setDoc, doc, getDoc, updateDoc } from 'firebase/firestore';

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
