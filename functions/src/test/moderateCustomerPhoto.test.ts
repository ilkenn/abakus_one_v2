import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `moderateCustomerPhoto` — Profile P.4.2B2.
 * Mirrors `updateBranchOperatingHours.test.ts`'s exact staff-auth test
 * shape (`mintStaffIdToken`, raw HTTP against the callable wire protocol).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const MODERATE_URL = fn("moderateCustomerPhoto");

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

async function signUpAnonymously(): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; refreshToken: string; localId: string };
  assert.strictEqual(response.status, 200);
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  assert.strictEqual(response.status, 200);
  return body.id_token;
}

async function mintStaffIdToken(organizationId: string, roles: string[]): Promise<{ idToken: string; uid: string }> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
  });
  return { idToken: await refreshIdToken(refreshToken), uid };
}

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${Date.now().toString(36)}-${idCounter}`;
}

interface SeedPhotoOptions {
  organizationId: string;
  customerId: string;
  photoId?: string;
  status?: string;
  isSelectedAsProfilePhoto?: boolean;
  rejectionReason?: string | null;
  revision?: number;
}

async function seedPhoto(opts: SeedPhotoOptions): Promise<string> {
  const photoId = opts.photoId ?? nextId("photo");
  await db().collection("customerPhotos").doc(photoId).set({
    customerId: opts.customerId,
    organizationId: opts.organizationId,
    photoRef: `tenants/${opts.organizationId}/customerPhotos/${opts.customerId}/${photoId}`,
    status: opts.status ?? "pendingReview",
    isSelectedAsProfilePhoto: opts.isSelectedAsProfilePhoto ?? false,
    uploadedAt: admin.firestore.Timestamp.now(),
    reviewedByStaffId: null,
    reviewedAt: null,
    rejectionReason: opts.rejectionReason ?? null,
    revision: opts.revision ?? 1,
  });
  return photoId;
}

async function seedProjection(organizationId: string, uid: string, selectedProfilePhotoRef: string) {
  await db().collection("customerPublicProfiles").doc(`${organizationId}_${uid}`).set({
    uid,
    organizationId,
    selectedProfilePhotoRef,
    updatedAt: admin.firestore.Timestamp.now(),
  });
}

// =========================================================================
// 1-3. Authorization
// =========================================================================

test("1. an authorized same-org staff member approves a pending photo", async () => {
  const organizationId = nextId("org");
  const { idToken, uid: staffUid } = await mintStaffIdToken(organizationId, ["manager"]);
  const photoId = await seedPhoto({ organizationId, customerId: "alice" });

  const { httpStatus, body } = await callCallable(
    MODERATE_URL,
    { photoId, action: "approve" },
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "approved");
  assert.strictEqual(body.result?.idempotent, false);

  const photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.status, "approved");
  assert.strictEqual(photo.data()!.reviewedByStaffId, staffUid);
});

test("2. an unauthorized customer (no staff claims at all) cannot moderate", async () => {
  const organizationId = nextId("org");
  const { idToken } = await signUpAnonymously();
  const photoId = await seedPhoto({ organizationId, customerId: "alice" });

  const { httpStatus, body } = await callCallable(
    MODERATE_URL,
    { photoId, action: "approve" },
    idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");

  const photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.status, "pendingReview", "the photo was never mutated");
});

test("3. staff of a DIFFERENT organization cannot moderate a photo belonging to another tenant", async () => {
  const photoOrg = nextId("org");
  const staffOrg = nextId("org");
  const { idToken } = await mintStaffIdToken(staffOrg, ["manager"]);
  const photoId = await seedPhoto({ organizationId: photoOrg, customerId: "alice" });

  const { httpStatus, body } = await callCallable(
    MODERATE_URL,
    { photoId, action: "approve" },
    idToken,
  );
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");

  const photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.status, "pendingReview");
});

test("base staff role (no moderateCustomerPhotos permission) cannot moderate", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["staff"]);
  const photoId = await seedPhoto({ organizationId, customerId: "alice" });

  const { httpStatus } = await callCallable(MODERATE_URL, { photoId, action: "approve" }, idToken);
  assert.strictEqual(httpStatus, 403);
});

// =========================================================================
// 4-6. Transition handling
// =========================================================================

test("4. reject records the rejection reason correctly", async () => {
  const organizationId = nextId("org");
  const { idToken, uid: staffUid } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({ organizationId, customerId: "alice" });

  const { httpStatus, body } = await callCallable(
    MODERATE_URL,
    { photoId, action: "reject", rejectionReason: "blurry" },
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "rejected");

  const photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.status, "rejected");
  assert.strictEqual(photo.data()!.rejectionReason, "blurry");
  assert.strictEqual(photo.data()!.reviewedByStaffId, staffUid);
  assert.ok(photo.data()!.reviewedAt);
});

test("5. an invalid transition — acting on an already-removed (terminal) photo — is rejected", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({ organizationId, customerId: "alice", status: "removed", revision: 3 });

  const { httpStatus, body } = await callCallable(
    MODERATE_URL,
    { photoId, action: "approve" },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");

  const photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.status, "removed");
  assert.strictEqual(photo.data()!.revision, 3, "revision is untouched by a rejected transition");
});

test("6. revision increments by exactly 1 per real transition", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({ organizationId, customerId: "alice", revision: 1 });

  await callCallable(MODERATE_URL, { photoId, action: "returnToReview" }, idToken);
  let photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.revision, 2);

  await callCallable(MODERATE_URL, { photoId, action: "approve" }, idToken);
  photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.revision, 3);
});

// =========================================================================
// 7-8. Idempotency / audit
// =========================================================================

test("7. moderation replay (same action, already in target state) is idempotent — no further mutation", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({ organizationId, customerId: "alice" });

  const first = await callCallable(MODERATE_URL, { photoId, action: "approve" }, idToken);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(first.body.result?.idempotent, false);

  const second = await callCallable(MODERATE_URL, { photoId, action: "approve" }, idToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.idempotent, true);

  const photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.revision, 2, "the replay did not bump revision a second time");
});

test("8. exactly one moderation audit entry is produced per real transition — a replay adds none", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({ organizationId, customerId: "alice" });

  await callCallable(MODERATE_URL, { photoId, action: "approve" }, idToken);
  await callCallable(MODERATE_URL, { photoId, action: "approve" }, idToken); // replay

  const auditSnap = await db().collection("auditEvents").where("photoId", "==", photoId).get();
  assert.strictEqual(auditSnap.size, 1, "exactly one audit entry exists despite the replay");
  assert.strictEqual(auditSnap.docs[0].data().action, "approve");
  assert.strictEqual(auditSnap.docs[0].data().beforeStatus, "pendingReview");
  assert.strictEqual(auditSnap.docs[0].data().afterStatus, "approved");
});

// =========================================================================
// 24-28. Moderating a currently-selected photo
// =========================================================================

test("24. rejecting the currently-selected photo clears isSelectedAsProfilePhoto atomically", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    status: "approved",
    isSelectedAsProfilePhoto: true,
  });
  const photoRef = (await db().collection("customerPhotos").doc(photoId).get()).data()!.photoRef as string;
  await seedProjection(organizationId, "alice", photoRef);

  const { httpStatus, body } = await callCallable(
    MODERATE_URL,
    { photoId, action: "reject", rejectionReason: "policy violation" },
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.clearedPublicSelection, true);

  const photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.isSelectedAsProfilePhoto, false);
});

test("25. rejecting the currently-selected photo clears the public projection atomically, in the same operation", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    status: "approved",
    isSelectedAsProfilePhoto: true,
  });
  const photoRef = (await db().collection("customerPhotos").doc(photoId).get()).data()!.photoRef as string;
  await seedProjection(organizationId, "alice", photoRef);

  await callCallable(MODERATE_URL, { photoId, action: "reject" }, idToken);

  const projection = await db().collection("customerPublicProfiles").doc(`${organizationId}_alice`).get();
  assert.strictEqual(projection.data()!.selectedProfilePhotoRef, null);
});

test("26. removing the currently-selected photo does the same — flag and projection both cleared", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    status: "approved",
    isSelectedAsProfilePhoto: true,
  });
  const photoRef = (await db().collection("customerPhotos").doc(photoId).get()).data()!.photoRef as string;
  await seedProjection(organizationId, "alice", photoRef);

  await callCallable(MODERATE_URL, { photoId, action: "remove" }, idToken);

  const photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.isSelectedAsProfilePhoto, false);
  const projection = await db().collection("customerPublicProfiles").doc(`${organizationId}_alice`).get();
  assert.strictEqual(projection.data()!.selectedProfilePhotoRef, null);
});

test("27. no automatic fallback photo is ever selected when the selected photo is cleared", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const selectedPhotoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    status: "approved",
    isSelectedAsProfilePhoto: true,
  });
  const otherApprovedPhotoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    status: "approved",
    isSelectedAsProfilePhoto: false,
  });
  const selectedPhotoRef = (await db().collection("customerPhotos").doc(selectedPhotoId).get()).data()!
    .photoRef as string;
  await seedProjection(organizationId, "alice", selectedPhotoRef);

  await callCallable(MODERATE_URL, { photoId: selectedPhotoId, action: "reject" }, idToken);

  const other = await db().collection("customerPhotos").doc(otherApprovedPhotoId).get();
  assert.strictEqual(other.data()!.isSelectedAsProfilePhoto, false, "no automatic replacement was chosen");
  const projection = await db().collection("customerPublicProfiles").doc(`${organizationId}_alice`).get();
  assert.strictEqual(projection.data()!.selectedProfilePhotoRef, null);
});

test("28. the moderation audit entry records that the public selection was cleared — no separate fake customer-selection event", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    status: "approved",
    isSelectedAsProfilePhoto: true,
  });
  const photoRef = (await db().collection("customerPhotos").doc(photoId).get()).data()!.photoRef as string;
  await seedProjection(organizationId, "alice", photoRef);

  await callCallable(MODERATE_URL, { photoId, action: "reject" }, idToken);

  const auditSnap = await db().collection("auditEvents").where("photoId", "==", photoId).get();
  assert.strictEqual(auditSnap.size, 1, "exactly one audit entry — the moderation event itself");
  assert.strictEqual(auditSnap.docs[0].data().type, "customerPhoto.moderated");
  assert.strictEqual(auditSnap.docs[0].data().clearedPublicSelection, true);

  const selectionAuditSnap = await db()
    .collection("auditEvents")
    .where("type", "==", "customerPhoto.selected")
    .where("photoId", "==", photoId)
    .get();
  assert.strictEqual(selectionAuditSnap.size, 0, "no fake customer-selection event was emitted");
});

// =========================================================================
// 29 (partial). Public safety — moderation path
// =========================================================================

test("29a. a pending (never approved) photo can never populate the public projection via moderation alone", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({ organizationId, customerId: "alice" });

  await callCallable(MODERATE_URL, { photoId, action: "reject", rejectionReason: "no" }, idToken);

  const projection = await db().collection("customerPublicProfiles").doc(`${organizationId}_alice`).get();
  assert.strictEqual(projection.exists, false, "moderation alone never creates a public projection for a never-selected photo");
});
