import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `selectCustomerProfilePhoto` — Profile
 * P.4.2B2. Mirrors `customerPhotoUploadGrants.test.ts`'s exact real-
 * phone-auth pattern (this callable also requires a real, phone-verified
 * customer identity).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SELECT_URL = fn("selectCustomerProfilePhoto");

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});

const db = () => admin.firestore();

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

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${Date.now().toString(36)}-${idCounter}`;
}

async function seedTenantCustomer(organizationId: string, uid: string) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({ organizationId, uid });
}

interface SeedPhotoOptions {
  organizationId: string;
  customerId: string;
  photoId?: string;
  status?: string;
  isSelectedAsProfilePhoto?: boolean;
}

async function seedPhoto(opts: SeedPhotoOptions): Promise<{ photoId: string; photoRef: string }> {
  const photoId = opts.photoId ?? nextId("photo");
  const photoRef = `tenants/${opts.organizationId}/customerPhotos/${opts.customerId}/${photoId}`;
  await db().collection("customerPhotos").doc(photoId).set({
    customerId: opts.customerId,
    organizationId: opts.organizationId,
    photoRef,
    status: opts.status ?? "approved",
    isSelectedAsProfilePhoto: opts.isSelectedAsProfilePhoto ?? false,
    uploadedAt: admin.firestore.Timestamp.now(),
    reviewedByStaffId: null,
    reviewedAt: null,
    rejectionReason: null,
    revision: 1,
  });
  return { photoId, photoRef };
}

async function getPhoto(photoId: string) {
  return db().collection("customerPhotos").doc(photoId).get();
}
async function getProjection(organizationId: string, uid: string) {
  return db().collection("customerPublicProfiles").doc(`${organizationId}_${uid}`).get();
}

// =========================================================================
// 9. Happy path
// =========================================================================

test("9. the owner selects their own approved photo", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const { photoId, photoRef } = await seedPhoto({ organizationId, customerId: uid });

  const { httpStatus, body } = await callCallable(SELECT_URL, { photoId, organizationId }, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.idempotent, false);
  assert.strictEqual(body.result?.photoRef, photoRef);

  const photo = await getPhoto(photoId);
  assert.strictEqual(photo.data()!.isSelectedAsProfilePhoto, true);
});

// =========================================================================
// 10-13. Only APPROVED may be selected
// =========================================================================

for (const status of ["pendingReview", "underReview", "rejected", "removed"]) {
  test(`a ${status} photo cannot be selected`, async () => {
    const organizationId = nextId("org");
    const { idToken, uid } = await createRealPhoneUser();
    await seedTenantCustomer(organizationId, uid);
    const { photoId } = await seedPhoto({ organizationId, customerId: uid, status });

    const { httpStatus, body } = await callCallable(SELECT_URL, { photoId, organizationId }, idToken);
    assert.strictEqual(httpStatus, 400);
    assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");

    const photo = await getPhoto(photoId);
    assert.strictEqual(photo.data()!.isSelectedAsProfilePhoto, false);
  });
}

// =========================================================================
// 14-15. Ownership / tenant scope
// =========================================================================

test("14. customer A cannot select customer B's photo", async () => {
  const organizationId = nextId("org");
  const { uid: bobUid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, bobUid);
  const { idToken: aliceToken, uid: aliceUid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, aliceUid);
  const { photoId } = await seedPhoto({ organizationId, customerId: bobUid });

  const { httpStatus, body } = await callCallable(SELECT_URL, { photoId, organizationId }, aliceToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");

  const photo = await getPhoto(photoId);
  assert.strictEqual(photo.data()!.isSelectedAsProfilePhoto, false);
});

test("15. a customer cannot select a photo that belongs to a different tenant than the one requested", async () => {
  const photoOrg = nextId("org");
  const requestedOrg = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(photoOrg, uid);
  await seedTenantCustomer(requestedOrg, uid);
  const { photoId } = await seedPhoto({ organizationId: photoOrg, customerId: uid });

  const { httpStatus, body } = await callCallable(
    SELECT_URL,
    { photoId, organizationId: requestedOrg },
    idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("a customer with no tenantCustomers record for the requested organization is rejected outright", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  const { photoId } = await seedPhoto({ organizationId, customerId: uid });

  const { httpStatus, body } = await callCallable(SELECT_URL, { photoId, organizationId }, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =========================================================================
// 16-17. Public projection creation / minimal content
// =========================================================================

test("16. the first selection creates the customerPublicProfiles projection — it did not need to pre-exist", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const { photoId } = await seedPhoto({ organizationId, customerId: uid });

  const before = await getProjection(organizationId, uid);
  assert.strictEqual(before.exists, false);

  await callCallable(SELECT_URL, { photoId, organizationId }, idToken);

  const after = await getProjection(organizationId, uid);
  assert.strictEqual(after.exists, true);
});

test("17. the projection contains only the minimal safe fields, referencing only the approved selected photo", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const { photoId, photoRef } = await seedPhoto({ organizationId, customerId: uid });

  await callCallable(SELECT_URL, { photoId, organizationId }, idToken);

  const projection = (await getProjection(organizationId, uid)).data()!;
  assert.strictEqual(projection.selectedProfilePhotoRef, photoRef);
  assert.strictEqual(projection.uid, uid);
  assert.strictEqual(projection.organizationId, organizationId);
  const fields = Object.keys(projection).sort();
  assert.deepStrictEqual(
    fields,
    ["organizationId", "selectedProfilePhotoRef", "uid", "updatedAt"],
    "no rejection reason, reviewer identity, moderation history, or other private field ever appears here",
  );
});

// =========================================================================
// 18-19. Exactly-one-selected invariant
// =========================================================================

test("18. selecting a second photo clears the first photo's selected flag", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const { photoId: photoA } = await seedPhoto({ organizationId, customerId: uid, isSelectedAsProfilePhoto: true });
  const { photoId: photoB } = await seedPhoto({ organizationId, customerId: uid });
  await db().collection("customerPublicProfiles").doc(`${organizationId}_${uid}`).set({
    uid,
    organizationId,
    selectedProfilePhotoRef: (await getPhoto(photoA)).data()!.photoRef,
    updatedAt: admin.firestore.Timestamp.now(),
  });

  await callCallable(SELECT_URL, { photoId: photoB, organizationId }, idToken);

  const a = await getPhoto(photoA);
  const b = await getPhoto(photoB);
  assert.strictEqual(a.data()!.isSelectedAsProfilePhoto, false);
  assert.strictEqual(b.data()!.isSelectedAsProfilePhoto, true);
});

test("19. exactly one selected flag remains across the customer's whole gallery after switching", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const photoIds: string[] = [];
  for (let i = 0; i < 5; i += 1) {
    const { photoId } = await seedPhoto({ organizationId, customerId: uid });
    photoIds.push(photoId);
  }

  await callCallable(SELECT_URL, { photoId: photoIds[0], organizationId }, idToken);
  await callCallable(SELECT_URL, { photoId: photoIds[2], organizationId }, idToken);
  await callCallable(SELECT_URL, { photoId: photoIds[4], organizationId }, idToken);

  const snap = await db()
    .collection("customerPhotos")
    .where("customerId", "==", uid)
    .where("isSelectedAsProfilePhoto", "==", true)
    .get();
  assert.strictEqual(snap.size, 1);
  assert.strictEqual(snap.docs[0].id, photoIds[4]);
});

// =========================================================================
// 20 / 32-33. Idempotency and audit
// =========================================================================

test("20 / 32 / 33. selecting the already-selected photo is idempotent — one audit entry total, no duplicate on replay", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const { photoId } = await seedPhoto({ organizationId, customerId: uid });

  const first = await callCallable(SELECT_URL, { photoId, organizationId }, idToken);
  assert.strictEqual(first.body.result?.idempotent, false);

  const second = await callCallable(SELECT_URL, { photoId, organizationId }, idToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.idempotent, true);

  const photo = await getPhoto(photoId);
  assert.strictEqual(photo.data()!.revision, 2, "the replay never bumped revision a second time");

  const auditSnap = await db()
    .collection("auditEvents")
    .where("type", "==", "customerPhoto.selected")
    .where("photoId", "==", photoId)
    .get();
  assert.strictEqual(auditSnap.size, 1, "exactly one selection audit event, despite the replay");
});

// =========================================================================
// 21-23. Concurrency
// =========================================================================

test("21-23. simultaneous select-A/select-B converge to exactly one winner, matched by the projection, with never two selected flags", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const { photoId: photoA } = await seedPhoto({ organizationId, customerId: uid });
  const { photoId: photoB } = await seedPhoto({ organizationId, customerId: uid });

  const [resultA, resultB] = await Promise.all([
    callCallable(SELECT_URL, { photoId: photoA, organizationId }, idToken),
    callCallable(SELECT_URL, { photoId: photoB, organizationId }, idToken),
  ]);
  assert.strictEqual(resultA.httpStatus, 200);
  assert.strictEqual(resultB.httpStatus, 200);

  const selectedSnap = await db()
    .collection("customerPhotos")
    .where("customerId", "==", uid)
    .where("isSelectedAsProfilePhoto", "==", true)
    .get();
  assert.strictEqual(selectedSnap.size, 1, "never two selected flags after concurrent selects");
  const winnerId = selectedSnap.docs[0].id;

  const projection = (await getProjection(organizationId, uid)).data()!;
  const winnerPhotoRef = (await getPhoto(winnerId)).data()!.photoRef;
  assert.strictEqual(projection.selectedProfilePhotoRef, winnerPhotoRef, "the public projection matches the actual final winner");
});

// =========================================================================
// 30. profilePicturePath is never touched
// =========================================================================

test("30. selecting a photo never writes to customers/{uid}.profilePicturePath — that field is not canonical", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  await db().collection("customers").doc(uid).set({ displayName: "Alice", email: null });
  const { photoId } = await seedPhoto({ organizationId, customerId: uid });

  await callCallable(SELECT_URL, { photoId, organizationId }, idToken);

  const customerDoc = await db().collection("customers").doc(uid).get();
  assert.strictEqual(
    Object.prototype.hasOwnProperty.call(customerDoc.data() ?? {}, "profilePicturePath"),
    false,
    "no profilePicturePath field was ever written by selection",
  );
});

// =========================================================================
// 34. cross-tenant/unauthorized attempts create no success audit
// =========================================================================

test("34. a rejected cross-customer selection attempt creates no audit event at all", async () => {
  const organizationId = nextId("org");
  const { uid: bobUid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, bobUid);
  const { idToken: aliceToken, uid: aliceUid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, aliceUid);
  const { photoId } = await seedPhoto({ organizationId, customerId: bobUid });

  await callCallable(SELECT_URL, { photoId, organizationId }, aliceToken);

  const auditSnap = await db()
    .collection("auditEvents")
    .where("type", "==", "customerPhoto.selected")
    .where("photoId", "==", photoId)
    .get();
  assert.strictEqual(auditSnap.size, 0, "a denied attempt never produces an audit entry");
});
