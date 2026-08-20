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
  purpose?: string | null;
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
    purpose: opts.purpose ?? null,
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

// CR.1.2's concurrency test (section 30-36 below) needs a real
// phone-verified customer identity to call `selectCustomerProfilePhoto`
// alongside a staff `moderateCustomerPhoto` call — mirrors
// `completeCustomerProfile.test.ts`'s exact createRealPhoneUser shape.
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

// =========================================================================
// 30-36. CR.1.2 — Auto-selection on approval of an onboarding-intent photo
// =========================================================================

test("30. approving an onboarding-intent photo with no existing selection auto-selects it — response, flag, and projection all agree", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    purpose: "profileOnboarding",
  });
  const photoRef = (await db().collection("customerPhotos").doc(photoId).get()).data()!.photoRef as string;

  const { httpStatus, body } = await callCallable(MODERATE_URL, { photoId, action: "approve" }, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.autoSelected, true);

  const photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.isSelectedAsProfilePhoto, true);

  const projection = await db().collection("customerPublicProfiles").doc(`${organizationId}_alice`).get();
  assert.ok(projection.exists);
  assert.strictEqual(projection.data()!.selectedProfilePhotoRef, photoRef);
  assert.strictEqual(projection.data()!.uid, "alice");
  assert.strictEqual(projection.data()!.organizationId, organizationId);
});

test("31. auto-selection is audited via a dedicated, system-actor customerPhoto.selected entry", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    purpose: "profileOnboarding",
  });

  await callCallable(MODERATE_URL, { photoId, action: "approve" }, idToken);

  const auditSnap = await db()
    .collection("auditEvents")
    .where("type", "==", "customerPhoto.selected")
    .where("photoId", "==", photoId)
    .get();
  assert.strictEqual(auditSnap.size, 1);
  assert.strictEqual(auditSnap.docs[0].data().actorId, "system");
  assert.strictEqual(auditSnap.docs[0].data().autoSelectedViaModeration, true);
});

test("32. approving an onboarding-intent photo does NOT overwrite an existing customer selection", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const alreadySelectedId = await seedPhoto({
    organizationId,
    customerId: "alice",
    status: "approved",
    isSelectedAsProfilePhoto: true,
  });
  const alreadySelectedRef = (await db().collection("customerPhotos").doc(alreadySelectedId).get()).data()!
    .photoRef as string;
  await seedProjection(organizationId, "alice", alreadySelectedRef);

  const onboardingPhotoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    purpose: "profileOnboarding",
  });

  const { httpStatus, body } = await callCallable(
    MODERATE_URL,
    { photoId: onboardingPhotoId, action: "approve" },
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.autoSelected, false, "an existing selection is never displaced");

  const onboardingPhoto = await db().collection("customerPhotos").doc(onboardingPhotoId).get();
  assert.strictEqual(onboardingPhoto.data()!.isSelectedAsProfilePhoto, false);

  const projection = await db().collection("customerPublicProfiles").doc(`${organizationId}_alice`).get();
  assert.strictEqual(
    projection.data()!.selectedProfilePhotoRef,
    alreadySelectedRef,
    "the older, already-chosen selection remains canonical",
  );
});

test("33. a rejected onboarding-intent photo is never selected — no auto-selection branch runs for a non-approve action", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    purpose: "profileOnboarding",
  });

  const { body } = await callCallable(
    MODERATE_URL,
    { photoId, action: "reject", rejectionReason: "blurry" },
    idToken,
  );
  assert.strictEqual(body.result?.autoSelected, false);

  const photo = await db().collection("customerPhotos").doc(photoId).get();
  assert.strictEqual(photo.data()!.isSelectedAsProfilePhoto, false);
  const projection = await db().collection("customerPublicProfiles").doc(`${organizationId}_alice`).get();
  assert.strictEqual(projection.exists, false);
});

test("34. auto-selection is scoped to the photo's own customer — a different customer's existing selection is untouched", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);

  const customerAPhotoId = await seedPhoto({
    organizationId,
    customerId: "customer-a",
    status: "approved",
    isSelectedAsProfilePhoto: true,
  });
  const customerARef = (await db().collection("customerPhotos").doc(customerAPhotoId).get()).data()!
    .photoRef as string;
  await seedProjection(organizationId, "customer-a", customerARef);

  const customerBPhotoId = await seedPhoto({
    organizationId,
    customerId: "customer-b",
    purpose: "profileOnboarding",
  });
  const customerBRef = (await db().collection("customerPhotos").doc(customerBPhotoId).get()).data()!
    .photoRef as string;

  const { body } = await callCallable(MODERATE_URL, { photoId: customerBPhotoId, action: "approve" }, idToken);
  assert.strictEqual(body.result?.autoSelected, true);

  const customerAProjection = await db()
    .collection("customerPublicProfiles")
    .doc(`${organizationId}_customer-a`)
    .get();
  assert.strictEqual(
    customerAProjection.data()!.selectedProfilePhotoRef,
    customerARef,
    "customer A's own selection is untouched by customer B's auto-selection",
  );

  const customerBProjection = await db()
    .collection("customerPublicProfiles")
    .doc(`${organizationId}_customer-b`)
    .get();
  assert.strictEqual(customerBProjection.data()!.selectedProfilePhotoRef, customerBRef);
});

test("35. idempotent replay of an already-approved, already-auto-selected photo never re-selects or duplicates the audit", async () => {
  const organizationId = nextId("org");
  const { idToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const photoId = await seedPhoto({
    organizationId,
    customerId: "alice",
    purpose: "profileOnboarding",
  });

  const first = await callCallable(MODERATE_URL, { photoId, action: "approve" }, idToken);
  assert.strictEqual(first.body.result?.autoSelected, true);

  const second = await callCallable(MODERATE_URL, { photoId, action: "approve" }, idToken);
  assert.strictEqual(second.body.result?.idempotent, true);
  assert.strictEqual(second.body.result?.autoSelected, false, "the idempotent replay branch never re-runs selection logic");

  const auditSnap = await db()
    .collection("auditEvents")
    .where("type", "==", "customerPhoto.selected")
    .where("photoId", "==", photoId)
    .get();
  assert.strictEqual(auditSnap.size, 1, "the replay produced no second auto-select audit entry");
});

test("36. a concurrent approve-with-auto-select and a manual select of a DIFFERENT already-approved photo resolve to exactly one canonical winner", async () => {
  const organizationId = nextId("org");
  const { idToken: staffIdToken } = await mintStaffIdToken(organizationId, ["admin"]);
  const { idToken: customerIdToken, uid: customerUid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, customerUid);

  const manuallySelectablePhotoId = await seedPhoto({
    organizationId,
    customerId: customerUid,
    status: "approved",
    isSelectedAsProfilePhoto: false,
  });
  const onboardingPhotoId = await seedPhoto({
    organizationId,
    customerId: customerUid,
    purpose: "profileOnboarding",
  });

  const [moderateResult, selectResult] = await Promise.all([
    callCallable(MODERATE_URL, { photoId: onboardingPhotoId, action: "approve" }, staffIdToken),
    callCallable(
      fn("selectCustomerProfilePhoto"),
      { photoId: manuallySelectablePhotoId, organizationId },
      customerIdToken,
    ),
  ]);

  assert.strictEqual(moderateResult.httpStatus, 200, JSON.stringify(moderateResult.body));
  assert.strictEqual(selectResult.httpStatus, 200, JSON.stringify(selectResult.body));

  // Self-consistency: never zero winners, never two — Firestore's own
  // transaction retry semantics (both paths read-then-write the same
  // projection doc) guarantee exactly one canonical selection survives
  // the race, whichever call's transaction happened to commit last.
  const selectedSnap = await db()
    .collection("customerPhotos")
    .where("customerId", "==", customerUid)
    .where("isSelectedAsProfilePhoto", "==", true)
    .get();
  assert.strictEqual(selectedSnap.size, 1, "exactly one photo ends up selected, never zero or two");

  const winnerRef = selectedSnap.docs[0].data().photoRef as string;
  const projection = await db().collection("customerPublicProfiles").doc(`${organizationId}_${customerUid}`).get();
  assert.strictEqual(
    projection.data()!.selectedProfilePhotoRef,
    winnerRef,
    "the projection always agrees with whichever photo is actually flagged selected",
  );
});
