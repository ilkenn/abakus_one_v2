// Masada Sipariş (dine-in table QR) — reusable dev/emulator table + table QR
// seed. Writes a real `restaurantTables` + `tableQrCodes` document pair,
// bound to this app's real canonical tenant chain (org-1 -> restaurant-1 ->
// branch-1 — the same chain `seed_dev_tenant.mjs` provisions). Requires that
// chain to already exist; run `npm run seed:dev-tenant` first.
//
// Mirrors `seed_dev_takeaway_qr.mjs`'s own reasoning exactly: `restaurantTables`/
// `tableQrCodes` have no dedicated `provision*` callable (no callable write
// path exists for either collection at all — `firestore.rules`'s fail-closed
// catch-all covers both), so the Admin SDK is the only, correct way anything
// ever writes to them. This script does not bypass any authorization/
// validation logic that exists elsewhere, because none exists to bypass.
//
// Field shapes mirror `RestaurantTable`/`TableQrCode`
// (`lib/features/qr/domain/models/{restaurant_table,table_qr_code}.dart`)
// plus the exact denormalized fields `functions/src/qrTokenResolution.ts`
// actually reads (`organizationId`/`restaurantId`/`branchId`/`isActive`/
// `status`/`displayName`/`branchDisplayName` on the table;
// `opaqueToken`/`tableId`/`status`/`expiresAt` on the QR code) — the same
// shape `functions/src/test/tableGuestSession.test.ts`'s own `seedTable`/
// `seedQrCode` helpers already use for this collection pair.
//
// The token used here (`DEV-ABAKUS-T12`) is the exact same literal
// `lib/features/qr/data/dev_table_qr_seed.dart`'s in-memory dev seed already
// uses for `validTokenTable12` — a QR code already printed/tested against
// that in-memory fake resolves identically against this real Firestore-backed
// backend now. Fixed, low-entropy, dev/emulator-only by design (mirrors
// `seed_dev_takeaway_qr.mjs`'s own token precedent) — never a production
// token generator.
//
// Safe to re-run any time — fixed document ids, `.set()` upserts rather than
// creating duplicates.
//
// **Faz R.1C.1.1** — `restaurantTables/table-12` now also carries
// `reservationAreaId: "garden"`, the canonical FK `assignReservationTable`
// (Faz R.1C.1) requires to match a table against a Reservation's own
// `confirmedAreaId`. `garden` is `seed_dev_reservation.mjs`'s own
// `reservationAreas/garden` ("Bahçe") — the same area table-12's existing
// `displayName`("Bahçe 1")/`areaName`("Bahçe") already imply, now made
// canonical instead of implied. This script therefore now **requires**
// `reservationAreas/garden` to already exist (referential consistency —
// never writes a dangling reference) — run `npm run seed:dev-reservation`
// first, or use `npm run seed:dev-table-qr`/`seed:dev-all`, both of which
// now chain it automatically in the correct order.
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set. Run via:
//
//   cd functions
//   firebase emulators:exec --only firestore,functions,auth \
//     "node scripts/seed_dev_tenant.mjs && node scripts/seed_dev_reservation.mjs && node scripts/seed_dev_table_qr.mjs"

import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[seed_dev_table_qr] FIRESTORE_EMULATOR_HOST is not set — refusing to " +
      "run against anything but the local emulator suite. Run via " +
      '`firebase emulators:exec --only firestore,functions,auth ' +
      '"node scripts/seed_dev_tenant.mjs && node scripts/seed_dev_table_qr.mjs"`.',
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const ORGANIZATION_ID = "org-1";
const RESTAURANT_ID = "restaurant-1";
const BRANCH_ID = "branch-1";
const BRANCH_DISPLAY_NAME = "Merkez Şube"; // matches seed_dev_tenant.mjs's real provisioned branch name
const TABLE_ID = "table-12";
const QR_CODE_ID = "dev-table-qr-table-12";
const QR_TOKEN = "DEV-ABAKUS-T12";
const RESERVATION_AREA_ID = "garden"; // seed_dev_reservation.mjs's "Bahçe" — Faz R.1C.1.1

const app = admin.initializeApp({ projectId: PROJECT_ID });

async function main() {
  const db = admin.firestore();

  const branchDoc = await db.collection("branches").doc(BRANCH_ID).get();
  if (!branchDoc.exists) {
    console.error(
      `[seed_dev_table_qr] branches/${BRANCH_ID} does not exist — run ` +
        "`npm run seed:dev-tenant` first to provision the canonical " +
        "org-1 -> restaurant-1 -> branch-1 chain.",
    );
    process.exit(1);
  }

  // Faz R.1C.1.1 — referential consistency: never write a table that claims
  // a `reservationAreaId` pointing at an area that doesn't exist yet.
  const areaDoc = await db.collection("reservationAreas").doc(RESERVATION_AREA_ID).get();
  if (!areaDoc.exists) {
    console.error(
      `[seed_dev_table_qr] reservationAreas/${RESERVATION_AREA_ID} does not exist — run ` +
        "`npm run seed:dev-reservation` first (or use `npm run seed:dev-table-qr`/" +
        "`seed:dev-all`, both of which already chain it in the correct order).",
    );
    process.exit(1);
  }

  const now = new Date();

  await db.collection("restaurantTables").doc(TABLE_ID).set({
    organizationId: ORGANIZATION_ID,
    restaurantId: RESTAURANT_ID,
    branchId: BRANCH_ID,
    branchDisplayName: BRANCH_DISPLAY_NAME,
    // No `floorPlans` document is seeded by this minimal dev seed — this id
    // is denormalized/reference-shaped only, matching
    // `dev_table_qr_seed.dart`'s own `'dev-floor-plan-1'` placeholder
    // convention; nothing currently joins against it.
    floorPlanId: "dev-floor-plan-1",
    displayName: "Bahçe 1",
    areaName: "Bahçe",
    // Faz R.1C.1.1 — the canonical FK `assignReservationTable` requires;
    // matches this table's own pre-existing areaName/displayName ("Bahçe").
    reservationAreaId: RESERVATION_AREA_ID,
    capacity: 4,
    status: "available",
    sortOrder: 12,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    revision: 1,
  });
  console.log(`[seed_dev_table_qr] restaurantTables/${TABLE_ID}: provisioned.`);

  await db.collection("tableQrCodes").doc(QR_CODE_ID).set({
    tableId: TABLE_ID,
    branchId: BRANCH_ID,
    opaqueToken: QR_TOKEN,
    status: "active",
    createdAt: now,
    updatedAt: now,
    revision: 1,
  });
  console.log(`[seed_dev_table_qr] tableQrCodes/${QR_CODE_ID}: provisioned.`);
  console.log(`[seed_dev_table_qr] token (dev/emulator only): ${QR_TOKEN}`);

  await app.delete();
}

main().catch((error) => {
  console.error("[seed_dev_table_qr] failed:", error);
  process.exitCode = 1;
});
