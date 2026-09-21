// PC Yönetici İnceleme Modu — Windows REST-Bridge follow-up (2026-09-20).
//
// Approves the Windows Flutter app's own real `requestDeviceRegistration`
// call (made via the new `RestCallableClient`, since `cloud_functions` has
// no native Windows implementation) — `respondToApprovalRequest` structurally
// forbids self-approval (`remoteApproval.ts`: `requestedByActorUid ===
// request.auth.uid` throws `permission-denied`, unconditional, even for
// `admin`), so a second, real staff account must call it. Mirrors
// `seed_dev_pos_showcase.mjs`'s own `seedApproverManager` pattern (real
// callables only — `assignStaffRole`/`grantStaffBranchAccess` — never a
// direct Firestore role write) but that script's own approver account is
// ephemeral (anonymous sign-up, never persisted) and gone once that script
// exits, so this script creates its own fresh one each run.
//
// UNLIKE every other seed_dev_*.mjs script: this one does NOT run under
// `firebase emulators:exec` (which starts a brand-new, empty emulator
// instance) — it connects to the SAME already-running emulator the Windows
// app itself is pointed at, so it can see the pending approval request that
// app just created. Run it in a second terminal, after the emulator is
// already up and the app has attempted device registration once:
//
//   npm run approve:dev-admin-device
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set.

import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[approve_pending_dev_admin_device] FIRESTORE_EMULATOR_HOST is not set " +
      "— refusing to run against anything but the local emulator suite. " +
      "Run via `npm run approve:dev-admin-device` (sets it for you).",
  );
  process.exit(1);
}

// Deliberately NOT "demo-abakus-one-emulator" (every other seed script's own
// default when GCLOUD_PROJECT is unset) — this script must match whichever
// project id the Windows app's own RestCallableClient actually targets
// (AppEnvironmentConfig.development.firebaseProjectId), since it needs to
// see THAT app's real pending request, not a fresh/unrelated emulator
// project. Override via GCLOUD_PROJECT if a local setup genuinely differs.
const PROJECT_ID = process.env.GCLOUD_PROJECT || "abakus-one-dev";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST
  ? `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`
  : "http://127.0.0.1:9099";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const fn = (name) => `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/${name}`;

const ORGANIZATION_ID = "org-1";
const BRANCH_ID = "branch-1";
// Must match seed_dev_staff.mjs's own DEV_ADMIN_EMAIL/DEV_ADMIN_PASSWORD —
// hand-synced, same accepted-risk shape as this codebase's other
// Dart<->script constant pairs.
const DEV_ADMIN_EMAIL = "admin@abakus.dev";
const DEV_ADMIN_PASSWORD = "abakus-dev-admin-2026";

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

async function callCallable(url, data, idToken) {
  const headers = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = await response.json();
  if (body.error) {
    throw new Error(`${url} failed: ${body.error.status} — ${body.error.message}`);
  }
  return body.result;
}

async function signInWithEmail(email, password) {
  const response = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const body = await response.json();
  if (body.error) {
    throw new Error(`Could not sign in as "${email}": ${JSON.stringify(body.error)}`);
  }
  return { idToken: body.idToken, uid: body.localId };
}

async function signUpAnonymously() {
  const response = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = await response.json();
  return { idToken: body.idToken, uid: body.localId };
}

/** A staff member solely to approve the dev admin's own pending device request — never signed into by the app. */
async function seedApproverManager(adminIdToken) {
  const { idToken, uid } = await signUpAnonymously();
  await db.collection("memberships").doc(`${ORGANIZATION_ID}_${uid}`).set({
    organizationId: ORGANIZATION_ID, uid, roles: ["manager"], branchAccess: [], restaurantAccess: [], status: "active", version: 1,
  });
  await callCallable(fn("assignStaffRole"), { organizationId: ORGANIZATION_ID, targetUid: uid, role: "manager" }, adminIdToken);
  await callCallable(fn("grantStaffBranchAccess"), { organizationId: ORGANIZATION_ID, targetUid: uid, branchId: BRANCH_ID }, adminIdToken);
  await callCallable(fn("syncOwnStaffClaims"), {}, idToken);
  return { uid, idToken };
}

async function main() {
  console.log(`[approve_pending_dev_admin_device] signing in as "${DEV_ADMIN_EMAIL}"...`);
  const admin1 = await signInWithEmail(DEV_ADMIN_EMAIL, DEV_ADMIN_PASSWORD);

  console.log("[approve_pending_dev_admin_device] looking for a pending device-activation request...");
  const pending = await db
    .collection("remoteApprovalRequests")
    .where("organizationId", "==", ORGANIZATION_ID)
    .where("branchId", "==", BRANCH_ID)
    .where("actionType", "==", "deviceActivation")
    .where("requestedByActorUid", "==", admin1.uid)
    .where("status", "==", "pending")
    .limit(1)
    .get();

  if (pending.empty) {
    console.log(
      "[approve_pending_dev_admin_device] no pending device-activation request found for " +
        `uid=${admin1.uid} — nothing to approve. Trigger device registration in the app first ` +
        "(this is expected if it was already approved by a previous run, or not requested yet).",
    );
    return;
  }

  const requestId = pending.docs[0].id;
  console.log(`[approve_pending_dev_admin_device] found pending request "${requestId}" — creating a real approver account...`);
  const approver = await seedApproverManager(admin1.idToken);

  await callCallable(fn("respondToApprovalRequest"), { requestId, decision: "approved" }, approver.idToken);
  console.log(`[approve_pending_dev_admin_device] approved "${requestId}". The app's own Firestore status ` +
    "listener should pick this up and complete the trusted-device session automatically.");
}

main().catch((error) => {
  console.error("[approve_pending_dev_admin_device] failed:", error);
  process.exitCode = 1;
});
