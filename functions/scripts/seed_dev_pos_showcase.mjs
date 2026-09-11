// PC Yönetici İnceleme Modu — dev/emulator seed that populates Masalar
// (Tables), KDS, Paket Servis (Takeaway), and Kasa (Cash Register) with
// real, live data so `flutter run -d windows` (or chrome) has something to
// browse immediately after signing in as the dev admin.
//
// Mirrors `seed_dev_tenant.mjs`'s own established reasoning: every write
// here goes through the REAL callables (`openTableGuestSession`,
// `submitDineInOrder`, `submitTakeawayOrder`, `requestCashSessionOpen`,
// etc.) — never a direct Firestore write for anything that has a real
// writer — so this script can never silently produce a document shape the
// functions themselves would have rejected, and it exercises the exact
// same authorization/validation path a real device would.
//
// PREREQUISITES (run first, or use `npm run seed:dev-pos-showcase` which
// chains all of them): seed_dev_tenant.mjs, seed_dev_staff.mjs,
// seed_dev_pos_entitlement.mjs, seed_dev_catalog.mjs, seed_dev_table_qr.mjs,
// seed_dev_takeaway_qr.mjs.
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set — this
// script signs in as the seeded dev admin and mints trusted-device/cash
// sessions, which must never happen against a real Firebase project.

import admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[seed_dev_pos_showcase] FIRESTORE_EMULATOR_HOST is not set — refusing " +
      "to run against anything but the local emulator suite. Run via " +
      "`npm run seed:dev-pos-showcase`.",
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST
  ? `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`
  : "http://127.0.0.1:9099";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const fn = (name) => `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/${name}`;

const ORGANIZATION_ID = "org-1";
const BRANCH_ID = "branch-1";
// Must match seed_dev_staff.mjs's own DEV_ADMIN_EMAIL/DEV_ADMIN_PASSWORD —
// hand-synced, same accepted-risk shape as this codebase's other
// Dart<->script constant pairs (no shared-import mechanism between them).
const DEV_ADMIN_EMAIL = "admin@abakus.dev";
const DEV_ADMIN_PASSWORD = "abakus-dev-admin-2026";
// From seed_dev_table_qr.mjs / seed_dev_takeaway_qr.mjs.
const TABLE_QR_TOKEN = "DEV-ABAKUS-T12";
const TAKEAWAY_QR_TOKEN = "DEV-TAKEAWAY-BRANCH-1-TOKEN";

const app = admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

let idCounter = 0;
function nextId(prefix) {
  idCounter += 1;
  return `${prefix}-${Date.now().toString(36)}-${idCounter}`;
}

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

async function signUpAnonymously() {
  const response = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = await response.json();
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function signInWithEmail(email, password) {
  const response = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const body = await response.json();
  if (body.error) {
    throw new Error(
      `Could not sign in as "${email}" — did seed_dev_staff.mjs run first? (${JSON.stringify(body.error)})`,
    );
  }
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

function generateDeviceKeyPair() {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
    sign: (nonce) => cryptoSign(null, Buffer.from(nonce, "utf8"), privateKey).toString("base64"),
  };
}

/** A staff member solely to approve requests the dev admin triggers — never signed into by the app. Mirrors this session's own established two-actor (staff + approver) pattern. */
async function seedApproverManager(adminIdToken) {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db.collection("memberships").doc(`${ORGANIZATION_ID}_${uid}`).set({
    organizationId: ORGANIZATION_ID, uid, roles: ["manager"], branchAccess: [], restaurantAccess: [], status: "active", version: 1,
  });
  await callCallable(fn("assignStaffRole"), { organizationId: ORGANIZATION_ID, targetUid: uid, role: "manager" }, adminIdToken);
  await callCallable(fn("grantStaffBranchAccess"), { organizationId: ORGANIZATION_ID, targetUid: uid, branchId: BRANCH_ID }, adminIdToken);
  await callCallable(fn("syncOwnStaffClaims"), {}, idToken);
  return { uid, idToken: await refreshIdToken(refreshToken) };
}
async function refreshIdToken(refreshToken) {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = await response.json();
  return body.id_token;
}

async function main() {
  console.log("[seed_dev_pos_showcase] signing in as the seeded dev admin...");
  const admin1 = await signInWithEmail(DEV_ADMIN_EMAIL, DEV_ADMIN_PASSWORD);
  await callCallable(fn("syncOwnStaffClaims"), {}, admin1.idToken);
  // Org-level "admin" role membership does not itself imply branch access —
  // requireBranchAccess (device registration, cash register, etc.) still
  // needs an explicit grant, exactly like any other role. Idempotent.
  await callCallable(fn("grantStaffBranchAccess"), { organizationId: ORGANIZATION_ID, targetUid: admin1.uid, branchId: BRANCH_ID }, admin1.idToken);
  await callCallable(fn("syncOwnStaffClaims"), {}, admin1.idToken);
  admin1.idToken = await refreshIdToken(admin1.refreshToken);

  const approver = await seedApproverManager(admin1.idToken);
  console.log("[seed_dev_pos_showcase] approver manager account ready (internal use only, never signed into by the app).");

  // --- Trusted device session for the dev admin (POS/Kasa callables require this) ---
  const device = generateDeviceKeyPair();
  const reg = await callCallable(fn("requestDeviceRegistration"), {
    organizationId: ORGANIZATION_ID, branchId: BRANCH_ID, platform: "windows",
    publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"],
  }, admin1.idToken);
  await callCallable(fn("respondToApprovalRequest"), { requestId: reg.approvalRequestId, decision: "approved" }, approver.idToken);
  const challenge = await callCallable(fn("requestDeviceChallenge"), {
    organizationId: ORGANIZATION_ID, branchId: BRANCH_ID, deviceId: reg.deviceId, purpose: "issue",
  }, admin1.idToken);
  const signature = device.sign(challenge.nonce);
  const session = await callCallable(fn("issueDeviceSession"), {
    organizationId: ORGANIZATION_ID, branchId: BRANCH_ID, deviceId: reg.deviceId,
    challengeId: challenge.challengeId, signature,
  }, admin1.idToken);
  const deviceCtx = {
    organizationId: ORGANIZATION_ID, branchId: BRANCH_ID,
    deviceId: reg.deviceId, deviceSessionId: session.sessionId,
  };
  console.log("[seed_dev_pos_showcase] trusted device session ready for the dev admin.");

  // =====================================================================
  // Masalar (Tables) + KDS — a real dine-in guest order on table-12,
  // both lines accepted -> real kitchenWorkItems land in KDS "queued".
  // =====================================================================
  const guestA = await signUpAnonymously();
  const openA = await callCallable(fn("openTableGuestSession"), { token: TABLE_QR_TOKEN }, guestA.idToken);
  const orderA = await callCallable(fn("submitDineInOrder"), {
    mode: "guestSession", submissionKey: nextId("key"), tableSessionId: openA.sessionId,
    items: [
      { kind: "product", productId: "prod_mexifit_bowl", quantity: 1 },
      { kind: "product", productId: "prod_ayran", quantity: 2 },
    ],
    guestDisplayName: "Demo Müşteri",
  }, guestA.idToken);
  await callCallable(fn("respondToDineInOrderLines"), {
    orderId: orderA.orderId,
    decisions: [{ lineIndex: 0, decision: "accept" }, { lineIndex: 1, decision: "accept" }],
  }, admin1.idToken);
  console.log("[seed_dev_pos_showcase] Masalar: table-12 dolu, sipariş kabul edildi -> KDS'te 2 iş kalemi.");

  // A couple more tables in varied states, for the branch overview grid.
  await db.collection("restaurantTables").doc("table-13").set({
    organizationId: ORGANIZATION_ID, restaurantId: "restaurant-1", branchId: BRANCH_ID,
    displayName: "Masa 13", isActive: true, activeTableSessionId: null, status: "available",
  }, { merge: true });
  await db.collection("restaurantTables").doc("table-14").set({
    organizationId: ORGANIZATION_ID, restaurantId: "restaurant-1", branchId: BRANCH_ID,
    displayName: "Masa 14", isActive: true, activeTableSessionId: null, status: "cleaning",
  }, { merge: true });
  console.log("[seed_dev_pos_showcase] Masalar: table-13 boş, table-14 temizleniyor olarak ayarlandı.");

  // =====================================================================
  // Paket Servis (Takeaway) — one order moved to "preparing", one left at
  // "pendingConfirmation" so the staff accept/reject flow has something to
  // act on too.
  // =====================================================================
  const guestB = await signUpAnonymously();
  const openTakeawayB = await callCallable(fn("openTakeawayGuestSession"), { token: TAKEAWAY_QR_TOKEN }, guestB.idToken);
  const takeawayOrder1 = await callCallable(fn("submitTakeawayOrder"), {
    submissionKey: nextId("key"), takeawaySessionId: openTakeawayB.sessionId,
    items: [{ kind: "product", productId: "prod_ayran", quantity: 2 }],
    contactFirstName: "Demo", contactLastName: "Müşteri", contactPhone: "+905551112233",
  }, guestB.idToken);
  await callCallable(fn("respondToTakeawayOrder"), { orderId: takeawayOrder1.orderId, decision: "confirm" }, admin1.idToken);
  await callCallable(fn("advanceTakeawayOrderStatus"), { orderId: takeawayOrder1.orderId, targetStatus: "preparing" }, admin1.idToken);

  const guestC = await signUpAnonymously();
  const openTakeawayC = await callCallable(fn("openTakeawayGuestSession"), { token: TAKEAWAY_QR_TOKEN }, guestC.idToken);
  await callCallable(fn("submitTakeawayOrder"), {
    submissionKey: nextId("key"), takeawaySessionId: openTakeawayC.sessionId,
    items: [{ kind: "product", productId: "prod_mexifit_bowl", quantity: 1 }],
    contactFirstName: "İkinci", contactLastName: "Müşteri", contactPhone: "+905551112244",
  }, guestC.idToken);
  console.log("[seed_dev_pos_showcase] Paket Servis: 1 sipariş hazırlanıyor, 1 sipariş onay bekliyor.");

  // =====================================================================
  // Kasa (Cash Register) — an open drawer session with an opening float
  // and one approved cash movement, so Kasa/Gün Sonu screens have real
  // data instead of an empty state.
  // =====================================================================
  const drawer = await callCallable(fn("createCashDrawer"), { ...deviceCtx, name: "Ana Kasa" }, admin1.idToken);
  const cashSession = await callCallable(fn("requestCashSessionOpen"), {
    ...deviceCtx, drawerId: drawer.drawerId, openingFloatAmountMinorUnits: 50000,
    currencyCode: "TRY", reason: "Gün başı açılış (demo verisi).",
  }, admin1.idToken);
  const movementReq = await callCallable(fn("requestCashMovement"), {
    ...deviceCtx, sessionId: cashSession.sessionId, movementType: "pettyCash",
    amountMinorUnits: 2000, reason: "Ofis malzemesi (demo verisi).",
  }, admin1.idToken);
  await callCallable(fn("respondToApprovalRequest"), { requestId: movementReq.approvalRequestId, decision: "approved" }, approver.idToken);
  console.log("[seed_dev_pos_showcase] Kasa: Ana Kasa açıldı (₺500 açılış bakiyesi), 1 nakit hareketi onaylandı.");

  console.log("");
  console.log("[seed_dev_pos_showcase] done. Flutter uygulamasında Yönetici/Personel Girişi ekranındaki");
  console.log(`  "Dev Admin ile Gir" kısayolunu kullanın, veya elle admin@abakus.dev / ${DEV_ADMIN_PASSWORD} ile giriş yapın.`);
  await app.delete();
}

main().catch((error) => {
  console.error("[seed_dev_pos_showcase] failed:", error);
  process.exitCode = 1;
});
