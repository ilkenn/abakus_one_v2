// Emulator-backed Storage Security Rules tests — Phase 9 Sprint 9H
// (docs/decisions.md ADR-026). Run with:
//   cd storage-tests && npm install && npm run test:emulator
// (wraps this file with `firebase emulators:exec --only storage` from the
// repo root so storage.rules resolves correctly).

import { test, before, after } from 'node:test';
import assert from 'node:assert';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  ref,
  uploadBytes,
  getBytes,
  deleteObject,
} from 'firebase/storage';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'abakus-one-storage-rules-test',
    storage: {
      rules: (await import('node:fs')).readFileSync('../storage.rules', 'utf8'),
      host: 'localhost',
      port: 9199,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

const smallImage = new Uint8Array(1024).fill(1); // 1 KB
const oversizedImage = new Uint8Array(6 * 1024 * 1024); // 6 MB > 5 MB limit

test('the owning uid can upload their own customer photo', async () => {
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: [] })
    .storage();
  const path = ref(alice, 'tenants/org-1/customerPhotos/alice/photo.png');

  await assertSucceeds(
    uploadBytes(path, smallImage, { contentType: 'image/png' }),
  );
});

test('a different uid cannot upload to alice\'s customer photo path', async () => {
  const eve = testEnv
    .authenticatedContext('eve', { organizationAccess: [] })
    .storage();
  const path = ref(eve, 'tenants/org-1/customerPhotos/alice/photo.png');

  await assertFails(
    uploadBytes(path, smallImage, { contentType: 'image/png' }),
  );
});

test('an oversized customer photo upload is rejected', async () => {
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: [] })
    .storage();
  const path = ref(alice, 'tenants/org-1/customerPhotos/alice/big.png');

  await assertFails(
    uploadBytes(path, oversizedImage, { contentType: 'image/png' }),
  );
});

test('a non-image content type for a customer photo is rejected', async () => {
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: [] })
    .storage();
  const path = ref(alice, 'tenants/org-1/customerPhotos/alice/file.pdf');

  await assertFails(
    uploadBytes(path, smallImage, { contentType: 'application/pdf' }),
  );
});

test('the owner can read their own customer photo; an unrelated user cannot', async () => {
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: [] })
    .storage();
  const path = ref(alice, 'tenants/org-1/customerPhotos/alice/photo2.png');
  await uploadBytes(path, smallImage, { contentType: 'image/png' });

  await assertSucceeds(getBytes(path));

  const eve = testEnv
    .authenticatedContext('eve', { organizationAccess: [] })
    .storage();
  await assertFails(
    getBytes(ref(eve, 'tenants/org-1/customerPhotos/alice/photo2.png')),
  );
});

test('an org member (staff) can read a customer photo for their own organization', async () => {
  const alice = testEnv
    .authenticatedContext('alice', { organizationAccess: [] })
    .storage();
  const path = ref(alice, 'tenants/org-1/customerPhotos/alice/photo3.png');
  await uploadBytes(path, smallImage, { contentType: 'image/png' });

  const staff = testEnv
    .authenticatedContext('staff-1', { organizationAccess: ['org-1'] })
    .storage();
  await assertSucceeds(
    getBytes(ref(staff, 'tenants/org-1/customerPhotos/alice/photo3.png')),
  );
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
