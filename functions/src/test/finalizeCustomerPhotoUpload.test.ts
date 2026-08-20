import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { getStorage } from "firebase-admin/storage";
import type { StorageEvent, StorageObjectData } from "firebase-functions/v2/storage";
import { finalizeCustomerPhotoUpload } from "../finalizeCustomerPhotoUpload";

/**
 * Emulator-backed tests for `finalizeCustomerPhotoUpload` — Profile
 * P.4.2B1. Two styles of test, deliberately kept separate:
 *
 * - Most tests call the exported `CloudFunction`'s own `.run(event)`
 *   method (the SDK's documented unit-test hook — see
 *   `firebase-functions/lib/v2/core.d.ts`'s own doc comment: "Use `run` to
 *   test a function") against a real Firestore emulator, with a
 *   synthetically-constructed `StorageEvent`. This exercises the exact
 *   same transaction/validation logic a real trigger invocation would,
 *   without needing a real Storage upload (and the event-delivery lag/
 *   polling that would imply) for every one of the many validation
 *   branches under test.
 * - Section F is the one genuine end-to-end test: a real object is
 *   uploaded to the real Storage emulator, which fires a real trigger
 *   event at the real deployed function, whose result is then polled for
 *   in real Firestore. Not faked — this is the one case the instructions
 *   specifically called out to exercise for real where the emulator
 *   stack supports it.
 *
 * Storage-Rules gating of who is allowed to upload to a given grant path
 * is already fully covered by `storage-tests/rules.test.js` (P.4.2A/
 * P.4.2A.1) — not re-tested here. This file uses the Admin SDK to write
 * bytes directly (bypassing Rules, same privilege level
 * `requestCustomerPhotoUploadGrant` itself already runs with) so each
 * test isolates the finalize function's OWN logic.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const BUCKET_NAME = `${EMULATOR_PROJECT_ID}.appspot.com`;

let app: admin.app.App;
before(() => {
  // Matches every other test file's exact convention (default app name,
  // relies on `--test-concurrency=1` serializing file execution so no two
  // files' `before`/`after` overlap) — see e.g. `customerPhotoUploadGrants
  // .test.ts`. `storageBucket` is the one addition this file needs, for
  // section F's real Storage upload.
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID, storageBucket: BUCKET_NAME });
});
after(async () => {
  await app.delete();
});

const db = () => admin.firestore();

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${Date.now().toString(36)}-${idCounter}`;
}

interface SeedGrantOptions {
  organizationId?: string;
  uid?: string;
  grantId?: string;
  status?: string;
  contentType?: string;
  createdAtMs?: number;
  expiresAtMs?: number;
  objectPathOverride?: string;
  purpose?: string | null;
}

async function seedGrant(opts: SeedGrantOptions = {}): Promise<{ grantId: string; objectPath: string }> {
  const organizationId = opts.organizationId ?? nextId("org");
  const uid = opts.uid ?? nextId("uid");
  const grantId = opts.grantId ?? nextId("grant");
  const now = Date.now();
  const createdAtMs = opts.createdAtMs ?? now;
  const expiresAtMs = opts.expiresAtMs ?? now + 15 * 60 * 1000;
  const objectPath =
    opts.objectPathOverride ?? `tenants/${organizationId}/customerPhotos/${uid}/${grantId}`;
  await db()
    .collection("customerPhotoUploadGrants")
    .doc(grantId)
    .set({
      uid,
      organizationId,
      objectPath,
      contentType: opts.contentType ?? "image/png",
      status: opts.status ?? "issued",
      createdAt: admin.firestore.Timestamp.fromMillis(createdAtMs),
      expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
      purpose: opts.purpose ?? null,
    });
  return { grantId, objectPath };
}

let generationCounter = 1_000_000;
function nextGeneration(): number {
  generationCounter += 1;
  return generationCounter;
}

function buildStorageEvent(overrides: Partial<StorageObjectData> & { name: string }): StorageEvent {
  const data: StorageObjectData = {
    bucket: BUCKET_NAME,
    contentType: "image/png",
    generation: nextGeneration(),
    metageneration: 1,
    id: `${BUCKET_NAME}/${overrides.name}`,
    size: 1024,
    storageClass: "STANDARD",
    timeCreated: new Date().toISOString(),
    ...overrides,
  };
  return {
    specversion: "1.0",
    id: nextId("event"),
    source: `//storage.googleapis.com/projects/_/buckets/${BUCKET_NAME}`,
    type: "google.cloud.storage.object.v1.finalized",
    time: new Date().toISOString(),
    data,
    bucket: BUCKET_NAME,
  } as StorageEvent;
}

async function getPhoto(grantId: string) {
  return db().collection("customerPhotos").doc(grantId).get();
}
async function getGrant(grantId: string) {
  return db().collection("customerPhotoUploadGrants").doc(grantId).get();
}
async function getAudit(grantId: string) {
  return db()
    .collection("auditEvents")
    .doc(`${grantId}-photo-submitted`)
    .get();
}

// =========================================================================
// A. Happy path — creation, quota conversion, deterministic identity
// =========================================================================

test("1. a valid finalized object creates a pendingReview CustomerPhoto", async () => {
  const { grantId, objectPath } = await seedGrant();
  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath }));

  const photo = await getPhoto(grantId);
  assert.ok(photo.exists, "photo document was created");
  assert.strictEqual(photo.data()!.status, "pendingReview");
  assert.strictEqual(photo.data()!.isSelectedAsProfilePhoto, false);
  assert.strictEqual(photo.data()!.photoRef, objectPath);
  assert.strictEqual(photo.data()!.revision, 1);
  assert.strictEqual(photo.data()!.reviewedByStaffId, null);
});

test("2. the grant becomes consumed once finalize succeeds", async () => {
  const { grantId, objectPath } = await seedGrant();
  const event = buildStorageEvent({ name: objectPath });
  await finalizeCustomerPhotoUpload.run(event);

  const grant = await getGrant(grantId);
  assert.strictEqual(grant.data()!.status, "consumed");
  assert.strictEqual(grant.data()!.photoId, grantId);
  assert.strictEqual(grant.data()!.objectGeneration, event.data.generation);
  assert.ok(grant.data()!.consumedAt, "consumedAt is set");
});

test("3. reservation-to-photo quota conversion is atomic — the combined outstanding+eligible count never drops to 0 or rises to 2", async () => {
  const organizationId = nextId("org");
  const uid = nextId("uid");
  const { objectPath } = await seedGrant({ organizationId, uid });

  const countBefore = await combinedQuotaCount(organizationId, uid);
  assert.strictEqual(countBefore, 1, "the issued grant alone counts as exactly 1 reserved slot");

  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath }));

  const countAfter = await combinedQuotaCount(organizationId, uid);
  assert.strictEqual(
    countAfter,
    1,
    "after finalize, the now-pendingReview photo alone counts as exactly 1 slot — never 0 (a gap) and never 2 (double-counted)",
  );
});

async function combinedQuotaCount(organizationId: string, uid: string): Promise<number> {
  const photosSnap = await db()
    .collection("customerPhotos")
    .where("customerId", "==", uid)
    .where("organizationId", "==", organizationId)
    .where("status", "in", ["pendingReview", "underReview", "approved"])
    .get();
  const grantsSnap = await db()
    .collection("customerPhotoUploadGrants")
    .where("uid", "==", uid)
    .where("organizationId", "==", organizationId)
    .where("status", "==", "issued")
    .get();
  return photosSnap.size + grantsSnap.size;
}

test("4. the created photo's document id is deterministically the grantId", async () => {
  const { grantId, objectPath } = await seedGrant();
  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath }));

  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.id, grantId);
});

test("18. CR.1.2 — a grant's purpose is copied server-authoritatively into the resulting photo's purpose field", async () => {
  const { grantId, objectPath } = await seedGrant({ purpose: "profileOnboarding" });
  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath }));

  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.data()!.purpose, "profileOnboarding");
});

test("19. CR.1.2 — a grant with no purpose produces a photo with purpose: null", async () => {
  const { grantId, objectPath } = await seedGrant();
  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath }));

  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.data()!.purpose, null);
});

test("16. a completed upload no longer counts only as an outstanding reservation — the grant drops out of the issued-grants quota query", async () => {
  const organizationId = nextId("org");
  const uid = nextId("uid");
  const { objectPath } = await seedGrant({ organizationId, uid });

  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath }));

  const stillIssuedSnap = await db()
    .collection("customerPhotoUploadGrants")
    .where("uid", "==", uid)
    .where("status", "==", "issued")
    .get();
  assert.strictEqual(stillIssuedSnap.size, 0, "the consumed grant no longer appears as an outstanding reservation");
});

// =========================================================================
// B. Expiry window — object creation time, never "now", decides validity
// =========================================================================

test("7. processing after expiresAt still accepts an upload whose OWN creation time was within the grant's valid window", async () => {
  const now = Date.now();
  const { grantId, objectPath } = await seedGrant({
    createdAtMs: now - 20 * 60 * 1000,
    expiresAtMs: now - 5 * 60 * 1000, // grant is "expired" by wall-clock now
  });
  // But the object's OWN immutable creation time is inside the grant's window.
  const timeCreated = new Date(now - 19 * 60 * 1000).toISOString();

  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath, timeCreated }));

  const photo = await getPhoto(grantId);
  assert.ok(photo.exists, "a legitimately-timed upload is accepted even though the grant has since expired");
});

test("8. an object created after the grant's own expiry window is rejected, even with a matching grant", async () => {
  const now = Date.now();
  const { grantId, objectPath } = await seedGrant({
    createdAtMs: now - 20 * 60 * 1000,
    expiresAtMs: now - 5 * 60 * 1000,
  });
  // Object creation time is AFTER expiresAt (well outside clock-skew tolerance).
  const timeCreated = new Date(now).toISOString();

  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath, timeCreated }));

  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.exists, false, "no CustomerPhoto is created for an object outside the grant's window");
  const grant = await getGrant(grantId);
  assert.strictEqual(grant.data()!.status, "issued", "the grant itself is left untouched, not consumed");
});

// =========================================================================
// C. Invalid-object rejection — permanent validation failures
// =========================================================================

test("9. no matching grant at all — no CustomerPhoto is ever created", async () => {
  const organizationId = nextId("org");
  const uid = nextId("uid");
  const grantId = nextId("grant");
  const objectPath = `tenants/${organizationId}/customerPhotos/${uid}/${grantId}`;

  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath }));

  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.exists, false);
});

test("10. a path claiming a different uid than the grant's own uid is rejected", async () => {
  const organizationId = nextId("org");
  const { grantId } = await seedGrant({ organizationId, uid: "alice" });
  // Same grantId, but the path segment claims a different uid than the grant record.
  const forgedPath = `tenants/${organizationId}/customerPhotos/eve/${grantId}`;

  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: forgedPath }));

  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.exists, false, "path-claimed uid never overrides the grant's own authorization truth");
});

test("11. a path claiming a different organizationId than the grant's own organizationId is rejected", async () => {
  const { grantId, objectPath } = await seedGrant({ organizationId: "org-1", uid: "alice" });
  const forgedPath = objectPath.replace("org-1", "org-2");

  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: forgedPath }));

  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.exists, false);
});

test("12. the grant's own stored objectPath not matching the path implied by (organizationId, uid, grantId) is rejected", async () => {
  const organizationId = "org-1";
  const uid = "alice";
  const grantId = nextId("grant");
  const correctPath = `tenants/${organizationId}/customerPhotos/${uid}/${grantId}`;
  // The grant record deliberately stores a WRONG objectPath (as if it had
  // been issued for a different grantId's path) while still being looked
  // up via this grantId — the finalize handler must never trust the
  // parsed path segments alone; it must cross-check against the grant's
  // own stored objectPath too.
  await seedGrant({
    organizationId,
    uid,
    grantId,
    objectPathOverride: `tenants/${organizationId}/customerPhotos/${uid}/some-other-grant-id`,
  });

  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: correctPath }));

  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.exists, false);
});

test("13. an unsupported (non-image) content type is rejected even with an otherwise-valid grant", async () => {
  const { grantId, objectPath } = await seedGrant({ contentType: "application/pdf" });

  await finalizeCustomerPhotoUpload.run(
    buildStorageEvent({ name: objectPath, contentType: "application/pdf" }),
  );

  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.exists, false);
});

test("a content type that differs from what the grant itself declared is rejected, even if both are technically images", async () => {
  const { grantId, objectPath } = await seedGrant({ contentType: "image/png" });

  await finalizeCustomerPhotoUpload.run(
    buildStorageEvent({ name: objectPath, contentType: "image/jpeg" }),
  );

  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.exists, false);
});

// =========================================================================
// D. Duplicate delivery / idempotency
// =========================================================================

test("5. duplicate finalize delivery for the same object produces exactly one CustomerPhoto", async () => {
  const { grantId, objectPath } = await seedGrant();
  const event = buildStorageEvent({ name: objectPath });

  await finalizeCustomerPhotoUpload.run(event);
  await finalizeCustomerPhotoUpload.run(event); // exact duplicate redelivery

  const photo = await getPhoto(grantId);
  assert.ok(photo.exists);
  assert.strictEqual(photo.data()!.revision, 1, "the second delivery did not re-touch the photo record");
});

test("6. duplicate finalize delivery produces exactly one audit event", async () => {
  const { grantId, objectPath } = await seedGrant();
  const event = buildStorageEvent({ name: objectPath });

  await finalizeCustomerPhotoUpload.run(event);
  await finalizeCustomerPhotoUpload.run(event);

  const audit = await getAudit(grantId);
  assert.ok(audit.exists, "exactly one audit record exists");
  assert.strictEqual(audit.data()!.type, "customerPhoto.submitted");
  assert.strictEqual(audit.data()!.grantId, grantId);
});

test("14. a consumed grant re-finalized under a DIFFERENT generation/object is treated as a conflict — no record is mutated", async () => {
  const { grantId, objectPath } = await seedGrant();
  const firstEvent = buildStorageEvent({ name: objectPath });
  await finalizeCustomerPhotoUpload.run(firstEvent);

  const photoAfterFirst = await getPhoto(grantId);
  const grantAfterFirst = await getGrant(grantId);

  const conflictingEvent = buildStorageEvent({ name: objectPath }); // fresh call => a new, different generation
  await finalizeCustomerPhotoUpload.run(conflictingEvent);

  const photoAfterConflict = await getPhoto(grantId);
  const grantAfterConflict = await getGrant(grantId);
  assert.deepStrictEqual(
    photoAfterConflict.data(),
    photoAfterFirst.data(),
    "the photo record from the first, legitimate finalize is untouched by the conflicting redelivery",
  );
  assert.deepStrictEqual(
    grantAfterConflict.data(),
    grantAfterFirst.data(),
    "the grant record is untouched — still reflects the original consuming generation",
  );
});

// =========================================================================
// E. Unrelated paths / retryability
// =========================================================================

test("unrelated Storage paths (not a customerPhotos upload) are ignored safely, no error thrown", async () => {
  await assert.doesNotReject(
    finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: "tenants/org-1/menuImages/bowl.png" })),
  );
  await assert.doesNotReject(
    finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: "some/totally/unrelated/path.png" })),
  );
});

test("15a. the trigger is registered with retry:true — the platform-level mechanism transient failures rely on", () => {
  const retry = finalizeCustomerPhotoUpload.__endpoint.eventTrigger?.retry;
  assert.strictEqual(retry, true);
});

test("15b. an unexpected error during the transaction propagates (throws) rather than being silently swallowed or treated as a permanent-invalid cleanup", async () => {
  const organizationId = nextId("org");
  const uid = nextId("uid");
  const grantId = nextId("grant");
  const objectPath = `tenants/${organizationId}/customerPhotos/${uid}/${grantId}`;
  // A malformed grant record (createdAt/expiresAt missing entirely) is not
  // a validation case this function's own logic anticipates and cleanly
  // rejects — it represents the kind of genuinely unexpected condition a
  // transient backend issue could also produce. The point under test is
  // the propagation behavior, not this specific cause.
  await db().collection("customerPhotoUploadGrants").doc(grantId).set({
    uid,
    organizationId,
    objectPath,
    contentType: "image/png",
    status: "issued",
    // createdAt / expiresAt deliberately omitted.
  });

  await assert.rejects(
    finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath })),
    "an unexpected error must propagate out of run() so retry:true can redeliver it — never get silently converted into a permanent rejection that deletes a real (if oddly-recorded) upload",
  );
  const photo = await getPhoto(grantId);
  assert.strictEqual(photo.exists, false, "no photo was created from the failed attempt");
});

// =========================================================================
// F. End-to-end: real Storage upload -> real trigger -> real Firestore photo
// =========================================================================

async function waitForPhotoDoc(grantId: string, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const snap = await getPhoto(grantId);
    if (snap.exists) return snap;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  return getPhoto(grantId);
}

test("F. a real Storage upload to a validly-granted path is finalized end-to-end into a real pendingReview CustomerPhoto", async () => {
  const { grantId, objectPath } = await seedGrant({ contentType: "image/png" });

  const bytes = Buffer.from(new Uint8Array(2048).fill(7));
  await getStorage().bucket(BUCKET_NAME).file(objectPath).save(bytes, {
    contentType: "image/png",
    resumable: false,
  });

  const photo = await waitForPhotoDoc(grantId);
  assert.ok(photo.exists, "the real Storage finalize event reached the real deployed trigger and created the photo");
  assert.strictEqual(photo.data()!.status, "pendingReview");
  assert.strictEqual(photo.data()!.photoRef, objectPath);

  const grant = await getGrant(grantId);
  assert.strictEqual(grant.data()!.status, "consumed");
});

// =========================================================================
// G. Cross-function integration: the max-10 cap still holds once a grant
// has actually been finalized into a real photo (not just left "issued")
// =========================================================================

const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const GRANT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/requestCustomerPhotoUploadGrant`;

async function callGrantCallable(data: Record<string, unknown>, idToken: string) {
  const response = await fetch(GRANT_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${idToken}` },
    body: JSON.stringify({ data }),
  });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;

async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
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
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}

async function seedTenantCustomer(organizationId: string, uid: string) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({ organizationId, uid });
}

test("17. the max-10 cap holds after a grant is actually finalized into a real photo — not just while it stays an outstanding reservation", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);

  // 9 pre-existing eligible photos, seeded directly (fast path — the
  // grant->finalize pipeline itself is already covered above).
  for (let i = 0; i < 9; i += 1) {
    await db()
      .collection("customerPhotos")
      .doc(nextId("photo"))
      .set({
        customerId: uid,
        organizationId,
        photoRef: `tenants/${organizationId}/customerPhotos/${uid}/${nextId("ref")}`,
        status: "approved",
        isSelectedAsProfilePhoto: false,
        uploadedAt: admin.firestore.Timestamp.now(),
        revision: 1,
      });
  }

  // Request and ACTUALLY finalize the 10th slot for real, through both
  // functions together — proving the cap accounts for a completed upload,
  // not merely an outstanding grant.
  const grantResult = await callGrantCallable(
    { organizationId, contentType: "image/png" },
    idToken,
  );
  assert.strictEqual(grantResult.httpStatus, 200);
  const grantId = grantResult.body.result?.grantId as string;
  const objectPath = grantResult.body.result?.objectPath as string;

  await finalizeCustomerPhotoUpload.run(buildStorageEvent({ name: objectPath }));
  const finalizedPhoto = await getPhoto(grantId);
  assert.ok(finalizedPhoto.exists, "the 10th slot is now a real, finalized pendingReview photo");

  // An 11th grant request must now be rejected — the finalized photo
  // (not an outstanding grant) is what's occupying the 10th slot.
  const eleventh = await callGrantCallable(
    { organizationId, contentType: "image/png" },
    idToken,
  );
  assert.strictEqual(eleventh.httpStatus, 429);
  assert.strictEqual(eleventh.body.error?.status, "RESOURCE_EXHAUSTED");
});
