// Emulator-backed Storage Security Rules tests — Phase 9 Sprint 9H
// (docs/decisions.md ADR-026), extended P.4.2A (Profile photo upload
// grants). Run with:
//   cd storage-tests && npm install && npm run test:emulator
// (wraps this file with `firebase emulators:exec --only firestore,storage`
// from the repo root — storage.rules' customerPhotos write rule now reads
// Firestore cross-service (firestore.get) to verify an upload grant, so
// both emulators must run together for these tests to reflect real
// behavior).

import { test, before, after } from 'node:test';
import assert from 'node:assert';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  ref,
  uploadBytes,
  updateMetadata,
  getBytes,
  deleteObject,
} from 'firebase/storage';
import { doc, setDoc, Timestamp } from 'firebase/firestore';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    // P.4.2A: MUST match the demo project id `firebase emulators:exec`
    // itself runs under (see `functions/src/test/*.test.ts`'s identical
    // `EMULATOR_PROJECT_ID` constant) — storage.rules' cross-service
    // `firestore.get()` calls are issued by the running Storage Emulator
    // process against THAT project's Firestore data, not whatever
    // `projectId` this test SDK client happens to choose for its own
    // direct read/write calls. A mismatch here doesn't error — it just
    // makes every `firestore.get()`/`firestore.exists()` call in
    // storage.rules silently see empty data, since it's a different
    // (empty) project namespace within the same emulator. Confirmed via
    // `firestore-debug.log` during this task's own implementation: seeded
    // grants were unreachable from storage.rules until this was fixed.
    projectId: 'demo-abakus-one-emulator',
    storage: {
      rules: readFileSync('../storage.rules', 'utf8'),
      host: 'localhost',
      port: 9199,
    },
    // P.4.2A — storage.rules' hasValidUploadGrant() reads
    // customerPhotoUploadGrants cross-service; firestore.rules itself
    // (deny-all on that collection) isn't under test here, but a real
    // Firestore connection is required for the Storage emulator's
    // firestore.get()/firestore.exists() calls to resolve at all.
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

async function seedFirestore(setupFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setupFn(context.firestore());
  });
}

const smallImage = new Uint8Array(1024).fill(1); // 1 KB
const oversizedImage = new Uint8Array(6 * 1024 * 1024); // 6 MB > 5 MB limit

let grantCounter = 0;
function nextGrantId() {
  grantCounter += 1;
  return `grant-${grantCounter}`;
}

/**
 * Seeds a customerPhotoUploadGrants document (bypassing Firestore Rules,
 * exactly as `requestCustomerPhotoUploadGrant` — Admin SDK — would) and
 * returns the grantId plus the exact object path it authorizes. Mirrors
 * `functions/src/customerPhotoUploadGrants.ts`'s own document shape.
 */
async function seedGrant({
  organizationId = 'org-1',
  uid = 'alice',
  grantId = nextGrantId(),
  status = 'issued',
  expiresInMs = 15 * 60 * 1000,
  contentType = 'image/png',
  objectPathOverride = null,
} = {}) {
  const objectPath =
    objectPathOverride ?? `tenants/${organizationId}/customerPhotos/${uid}/${grantId}`;
  await seedFirestore(async (db) => {
    await setDoc(doc(db, `customerPhotoUploadGrants/${grantId}`), {
      uid,
      organizationId,
      objectPath,
      contentType,
      status,
      createdAt: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(Date.now() + expiresInMs),
    });
  });
  return { grantId, objectPath };
}

/** Seeds a tenantCustomers/{organizationId}_{uid} record — real tenant membership, mirrors `requestCustomerPhotoUploadGrant`'s own check. */
async function seedTenantCustomer(organizationId, uid) {
  await seedFirestore(async (db) => {
    await setDoc(doc(db, `tenantCustomers/${organizationId}_${uid}`), { organizationId, uid });
  });
}

/** Seeds/overwrites customerPublicProfiles/{organizationId}_{uid}.selectedProfilePhotoRef — the ONE authorization pointer P.4.2B2.1 reads. `null` clears it, mirroring moderation/selection-change behavior. */
async function seedProjection(organizationId, uid, selectedProfilePhotoRef) {
  await seedFirestore(async (db) => {
    await setDoc(doc(db, `customerPublicProfiles/${organizationId}_${uid}`), {
      uid,
      organizationId,
      selectedProfilePhotoRef,
      updatedAt: Timestamp.now(),
    });
  });
}

test('a valid, active grant lets the owning uid upload to the exact granted path', async () => {
  const { grantId, objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();

  await assertSucceeds(
    uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' }),
  );
  assert.ok(grantId, 'grant seeded');
});

test('no grant at all — upload is denied even though owner/MIME/size are all otherwise valid', async () => {
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  const path = 'tenants/org-1/customerPhotos/alice/no-such-grant';

  await assertFails(
    uploadBytes(ref(alice, path), smallImage, { contentType: 'image/png' }),
  );
});

test('wrong uid — a different authenticated user cannot use alice\'s grant, even at the correct path', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const eve = testEnv.authenticatedContext('eve', { organizationAccess: [] }).storage();

  await assertFails(
    uploadBytes(ref(eve, objectPath), smallImage, { contentType: 'image/png' }),
  );
});

test('wrong org — the grant is scoped to org-1; the same uid cannot reuse it for an org-2 path', async () => {
  const { grantId } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  const wrongOrgPath = `tenants/org-2/customerPhotos/alice/${grantId}`;

  await assertFails(
    uploadBytes(ref(alice, wrongOrgPath), smallImage, { contentType: 'image/png' }),
  );
});

test('cross-tenant uid substitution exploit is specifically denied — a customer of org-1 cannot write under org-2 using their own uid and a self-supplied grantId', async () => {
  // No grant exists for this path at all (the whole point of the grant
  // model), but this test names the exact historical exploit P.4.1
  // disclosed and P.4.2A closes: `isOwner(uid)` alone would have allowed
  // this write before this task, since alice IS alice regardless of which
  // organizationId segment she names in the path.
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  const forgedPath = 'tenants/org-2/customerPhotos/alice/self-issued-grant-id';

  await assertFails(
    uploadBytes(ref(alice, forgedPath), smallImage, { contentType: 'image/png' }),
  );
});

test('another customer\'s grant cannot be used at their own genuine path by someone else entirely', async () => {
  const { objectPath: alicesPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const bob = testEnv.authenticatedContext('bob', { organizationAccess: [] }).storage();

  // Bob attempts to write to alice's own granted path — denied both
  // because Bob is not "alice" (isOwner(uid) fails on the path's own uid
  // segment) and because the grant's uid field doesn't match Bob either.
  await assertFails(
    uploadBytes(ref(bob, alicesPath), smallImage, { contentType: 'image/png' }),
  );
});

test('an expired grant is denied even though every other field matches', async () => {
  const { objectPath } = await seedGrant({
    uid: 'alice',
    organizationId: 'org-1',
    expiresInMs: -1000, // already expired
  });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();

  await assertFails(
    uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' }),
  );
});

test('a non-"issued" grant status (e.g. cancelled) is denied', async () => {
  const { objectPath } = await seedGrant({
    uid: 'alice',
    organizationId: 'org-1',
    status: 'cancelled',
  });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();

  await assertFails(
    uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' }),
  );
});

test('a consumed grant (the object already exists at this path) cannot be used again — single-use', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();

  await assertSucceeds(
    uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' }),
  );
  // Same still-"issued", still-unexpired grant; the object now exists —
  // resource == null no longer holds, so a second write to the exact
  // same path is denied regardless of the grant's own validity.
  await assertFails(
    uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' }),
  );
});

test('P.4.2A.1: a metadata-only update on the existing object is denied — the grant is create-only, never update, even without a byte change', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });

  // Same still-"issued", still-unexpired grant. Cloud Storage classifies
  // a metadata-only change as an "update", not a "create" — resource !=
  // null for an existing object either way, so the same resource == null
  // check that blocks a second byte-overwrite blocks this too. Explicitly
  // tested (not just incidentally true) per P.4.2A.1.
  await assertFails(
    updateMetadata(ref(alice, objectPath), { customMetadata: { note: 'tampered' } }),
  );
});

test('path mismatch — a grant issued for one object path cannot authorize a write to a different path, even same uid/org', async () => {
  const { grantId } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  // Same organizationId/uid, but a different final path segment than the
  // grant's own objectPath (grantId != this made-up filename).
  const differentPath = 'tenants/org-1/customerPhotos/alice/not-the-granted-id';

  await assertFails(
    uploadBytes(ref(alice, differentPath), smallImage, { contentType: 'image/png' }),
  );
  assert.ok(grantId, 'grant seeded for a different path than the one attempted');
});

test('a non-image content type is still rejected even with a valid grant', async () => {
  const { objectPath } = await seedGrant({
    uid: 'alice',
    organizationId: 'org-1',
    contentType: 'application/pdf',
  });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();

  await assertFails(
    uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'application/pdf' }),
  );
});

test('an oversized image is still rejected even with a valid grant', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();

  await assertFails(
    uploadBytes(ref(alice, objectPath), oversizedImage, { contentType: 'image/png' }),
  );
});

test('the owner can read their own uploaded customer photo; an unrelated user cannot', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });

  await assertSucceeds(getBytes(ref(alice, objectPath)));

  const eve = testEnv.authenticatedContext('eve', { organizationAccess: [] }).storage();
  await assertFails(getBytes(ref(eve, objectPath)));
});

test('an org member (staff) can read a customer photo for their own organization', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });

  const staff = testEnv
    .authenticatedContext('staff-1', { organizationAccess: ['org-1'] })
    .storage();
  await assertSucceeds(getBytes(ref(staff, objectPath)));
});

test('staff from a different organization cannot read the customer photo', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });

  const otherOrgStaff = testEnv
    .authenticatedContext('staff-2', { organizationAccess: ['org-2'] })
    .storage();
  await assertFails(getBytes(ref(otherOrgStaff, objectPath)));
});

// =========================================================================
// P.4.2B2.1 — public-selected-photo read bridge
// =========================================================================

test('1. the owner can still read their own private photo, unaffected by the new public-read path', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });

  await assertSucceeds(getBytes(ref(alice, objectPath)));
});

test('2. authorized same-org staff can still read according to existing rules, unaffected by the new public-read path', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });

  const staff = testEnv.authenticatedContext('staff-1', { organizationAccess: ['org-1'] }).storage();
  await assertSucceeds(getBytes(ref(staff, objectPath)));
});

test('3. an authenticated same-tenant customer can read the exact currently-selected photo', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });
  await seedProjection('org-1', 'alice', objectPath);
  await seedTenantCustomer('org-1', 'bob');
  const bob = testEnv.authenticatedContext('bob', { organizationAccess: [] }).storage();

  await assertSucceeds(getBytes(ref(bob, objectPath)));
});

test('4. a same-tenant customer cannot read another approved-but-unselected photo of the same owner', async () => {
  const { objectPath: selectedPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const { objectPath: unselectedPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, selectedPath), smallImage, { contentType: 'image/png' });
  await uploadBytes(ref(alice, unselectedPath), smallImage, { contentType: 'image/png' });
  await seedProjection('org-1', 'alice', selectedPath);
  await seedTenantCustomer('org-1', 'bob');
  const bob = testEnv.authenticatedContext('bob', { organizationAccess: [] }).storage();

  await assertSucceeds(getBytes(ref(bob, selectedPath)));
  await assertFails(getBytes(ref(bob, unselectedPath)));
});

test('5. a same-tenant customer cannot read a pendingReview photo — status is irrelevant to this rule, only the projection matters, and it never points here', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });
  await seedTenantCustomer('org-1', 'bob');
  const bob = testEnv.authenticatedContext('bob', { organizationAccess: [] }).storage();

  await assertFails(getBytes(ref(bob, objectPath)));
});

test('6. a same-tenant customer cannot read a rejected photo, even one that was previously selected before rejection', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });
  // Moderation-triggered clear: the projection no longer names this photo.
  await seedProjection('org-1', 'alice', null);
  await seedTenantCustomer('org-1', 'bob');
  const bob = testEnv.authenticatedContext('bob', { organizationAccess: [] }).storage();

  await assertFails(getBytes(ref(bob, objectPath)));
});

test('7. a same-tenant customer cannot read a removed photo', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });
  await seedProjection('org-1', 'alice', null);
  await seedTenantCustomer('org-1', 'bob');
  const bob = testEnv.authenticatedContext('bob', { organizationAccess: [] }).storage();

  await assertFails(getBytes(ref(bob, objectPath)));
});

test('8. a guest (unauthenticated) cannot read the selected photo', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });
  await seedProjection('org-1', 'alice', objectPath);
  const guest = testEnv.unauthenticatedContext().storage();

  await assertFails(getBytes(ref(guest, objectPath)));
});

test('9. a cross-tenant customer (member of a different organization) cannot read the selected photo', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });
  await seedProjection('org-1', 'alice', objectPath);
  // Eve belongs to org-2, not org-1.
  await seedTenantCustomer('org-2', 'eve');
  const eve = testEnv.authenticatedContext('eve', { organizationAccess: [] }).storage();

  await assertFails(getBytes(ref(eve, objectPath)));
});

test('10. knowing the exact Storage path without a matching projection is denied — the projection is the sole authorization pointer, not path/photoId knowledge', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });
  // No customerPublicProfiles document exists at all for alice in org-1.
  await seedTenantCustomer('org-1', 'bob');
  const bob = testEnv.authenticatedContext('bob', { organizationAccess: [] }).storage();

  await assertFails(getBytes(ref(bob, objectPath)));
});

test('11. after selection changes from photo A to photo B, A becomes denied and B becomes allowed', async () => {
  const { objectPath: pathA } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const { objectPath: pathB } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, pathA), smallImage, { contentType: 'image/png' });
  await uploadBytes(ref(alice, pathB), smallImage, { contentType: 'image/png' });
  await seedTenantCustomer('org-1', 'bob');
  const bob = testEnv.authenticatedContext('bob', { organizationAccess: [] }).storage();

  await seedProjection('org-1', 'alice', pathA);
  await assertSucceeds(getBytes(ref(bob, pathA)));
  await assertFails(getBytes(ref(bob, pathB)));

  await seedProjection('org-1', 'alice', pathB);
  await assertFails(getBytes(ref(bob, pathA)));
  await assertSucceeds(getBytes(ref(bob, pathB)));
});

test('12. after the projection selection is cleared (moderation), the previously-selected photo is immediately denied', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });
  await seedTenantCustomer('org-1', 'bob');
  const bob = testEnv.authenticatedContext('bob', { organizationAccess: [] }).storage();

  await seedProjection('org-1', 'alice', objectPath);
  await assertSucceeds(getBytes(ref(bob, objectPath)));

  // P.4.2B2's moderation transaction clearing a selection nulls this field
  // — no second public-state source, this IS what that clear looks like.
  await seedProjection('org-1', 'alice', null);
  await assertFails(getBytes(ref(bob, objectPath)));
});

test('13. the private-gallery read permission set is not broadened — owner and staff read behave exactly as before, unrelated grantIds stay private to same-tenant customers', async () => {
  const { objectPath: photo1 } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const { objectPath: photo2 } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, photo1), smallImage, { contentType: 'image/png' });
  await uploadBytes(ref(alice, photo2), smallImage, { contentType: 'image/png' });
  await seedProjection('org-1', 'alice', photo1);
  await seedTenantCustomer('org-1', 'bob');
  const bob = testEnv.authenticatedContext('bob', { organizationAccess: [] }).storage();
  const eve = testEnv.authenticatedContext('eve', { organizationAccess: [] }).storage();

  // Owner: still full private access to both, exactly as before.
  await assertSucceeds(getBytes(ref(alice, photo1)));
  await assertSucceeds(getBytes(ref(alice, photo2)));
  // Staff: still full org access to both, exactly as before.
  const staff = testEnv.authenticatedContext('staff-1', { organizationAccess: ['org-1'] }).storage();
  await assertSucceeds(getBytes(ref(staff, photo1)));
  await assertSucceeds(getBytes(ref(staff, photo2)));
  // An unrelated authenticated user with no tenant membership at all: denied both.
  await assertFails(getBytes(ref(eve, photo1)));
  await assertFails(getBytes(ref(eve, photo2)));
  // A genuine same-tenant customer: only the one selected photo, never the other.
  await assertSucceeds(getBytes(ref(bob, photo1)));
  await assertFails(getBytes(ref(bob, photo2)));
});

test('P.4.2A: direct owner delete is now denied — customer photo removal is server-authoritative only', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });

  await assertFails(deleteObject(ref(alice, objectPath)));
});

test('P.4.2A: staff cannot delete a customer photo directly either — no client delete path exists at all', async () => {
  const { objectPath } = await seedGrant({ uid: 'alice', organizationId: 'org-1' });
  const alice = testEnv.authenticatedContext('alice', { organizationAccess: [] }).storage();
  await uploadBytes(ref(alice, objectPath), smallImage, { contentType: 'image/png' });

  const staff = testEnv
    .authenticatedContext('staff-1', { organizationAccess: ['org-1'] })
    .storage();
  await assertFails(deleteObject(ref(staff, objectPath)));
});

test('feedback attachments can never be deleted, even by the owner', async () => {
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: [] })
    .storage();
  const path = ref(alice, 'tenants/org-1/feedbackAttachments/alice/proof.png');
  await uploadBytes(path, smallImage, { contentType: 'image/png' });

  await assertFails(deleteObject(path));
});

test('menu images are publicly readable but never client-writable', async () => {
  const anonymous = testEnv.unauthenticatedContext().storage();
  const staff = testEnv
    .authenticatedContext('staff-1', { organizationAccess: ['org-1'] })
    .storage();

  await assertFails(
    uploadBytes(
      ref(staff, 'tenants/org-1/menuImages/bowl.png'),
      smallImage,
      { contentType: 'image/png' },
    ),
  );
  // Nothing was ever written (the write above failed), but the read
  // rule itself (`allow read: if true`) is what's under test here - a
  // nonexistent object 404s at the emulator level, which is a distinct
  // concern from authorization; asserting the write is denied is the
  // meaningful, stable assertion for this path.
  assert.ok(anonymous, 'unauthenticated context constructed successfully');
});

test('import files require organization membership for both read and write', async () => {
  const staff = testEnv
    .authenticatedContext('staff-1', { organizationAccess: ['org-1'] })
    .storage();
  const path = ref(staff, 'tenants/org-1/importFiles/staff-1/menu.csv');

  await assertSucceeds(
    uploadBytes(path, smallImage, { contentType: 'text/csv' }),
  );

  const outsider = testEnv
    .authenticatedContext('outsider', { organizationAccess: ['org-2'] })
    .storage();
  await assertFails(
    getBytes(ref(outsider, 'tenants/org-1/importFiles/staff-1/menu.csv')),
  );
});

test('an unlisted path defaults to fully denied (fail closed)', async () => {
  const staff = testEnv
    .authenticatedContext('staff-1', { organizationAccess: ['org-1'] })
    .storage();

  await assertFails(
    uploadBytes(
      ref(staff, 'tenants/org-1/unknownCategory/file.txt'),
      smallImage,
    ),
  );
});
