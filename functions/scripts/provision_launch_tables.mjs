// 2026-10-28 — real-table + QR-token provisioning for the Cumartesi launch.
//
// There is, today, no real Cloud Function and no admin UI that creates a
// `restaurantTables` document or mints a `tableQrCodes` opaque token — every
// one of the 22 files across `functions/src/test` that write either
// collection does so only as a throwaway test fixture
// (`assignReservationTable.test.ts`'s own `seedRestaurantTable` is the most
// complete shape, mirrored below). This script is the first real,
// deliberately-written provisioning path for either collection, run once
// (and safely re-runnable) against a real Firebase project rather than the
// emulator, for the 14 physical tables Abaküs is launching with.
//
// WHY a direct Admin-SDK script, not a new callable: every other seed
// script in this directory that provisions real tenant data for a real
// project (as opposed to emulator-only dev fixtures) already writes
// directly via the Admin SDK — see this file's own precedent discussion in
// `docs/feature_status.md`'s 2026-10-28 entry. A reusable
// `provisionRestaurantTable` callable (for a future admin "Masalar" screen)
// is a reasonable fast-follow, deliberately not built here to stay in scope
// with what was actually asked for.
//
// SAFETY: requires an explicit `--project` matching an allow-listed real
// project id (refuses silently guessing) and real Admin SDK credentials
// (`GOOGLE_APPLICATION_CREDENTIALS` pointing at a service-account key —
// never hardcoded in this file, never committed). Idempotent: re-running
// never duplicates a table, never resets an already-occupied table's live
// `status`/`activeTableSessionId`, and never mints a second QR token for a
// table that already has an active one (which would silently invalidate an
// already-printed code).
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/staging-service-account.json \
//     node scripts/provision_launch_tables.mjs --project abakus-one-staging

import admin from "firebase-admin";
import { randomBytes } from "crypto";
import { writeFileSync, mkdirSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const ALLOWED_PROJECT_IDS = new Set(["abakus-one-staging", "abakusone"]);

const projectArgIndex = process.argv.indexOf("--project");
const PROJECT_ID = projectArgIndex !== -1 ? process.argv[projectArgIndex + 1] : null;

if (!PROJECT_ID || !ALLOWED_PROJECT_IDS.has(PROJECT_ID)) {
  console.error(
    "[provision_launch_tables] --project is required and must be one of: " +
      `${[...ALLOWED_PROJECT_IDS].join(", ")}. Got: ${PROJECT_ID ?? "(none)"}.`,
  );
  process.exit(1);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error(
    "[provision_launch_tables] GOOGLE_APPLICATION_CREDENTIALS is not set — " +
      "point it at a real service-account key for this project before " +
      "running. Refusing to fall back to any implicit/default credential.",
  );
  process.exit(1);
}

const ORGANIZATION_ID = "org-1";
const RESTAURANT_ID = "restaurant-1";
const BRANCH_ID = "branch-1";
const BRANCH_DISPLAY_NAME = "Merkez Şube";

const TABLES = [
  ...Array.from({ length: 7 }, (_, i) => ({
    tableId: `ic-${i + 1}`,
    displayName: `İç Masa ${i + 1}`,
    areaName: "İç Mekan",
    sortOrder: i,
  })),
  ...Array.from({ length: 7 }, (_, i) => ({
    tableId: `bahce-${i + 1}`,
    displayName: `Bahçe Masa ${i + 1}`,
    areaName: "Bahçe",
    sortOrder: 7 + i,
  })),
];

const app = admin.initializeApp({ projectId: PROJECT_ID });

function mintOpaqueToken() {
  // 24 random bytes, base64url — short enough for a compact QR, long
  // enough (192 bits) that guessing one is not a credible attack vector.
  return randomBytes(24).toString("base64url");
}

async function provisionTable(db, table) {
  const ref = db.collection("restaurantTables").doc(table.tableId);
  const existing = await ref.get();

  if (!existing.exists) {
    await ref.set({
      organizationId: ORGANIZATION_ID,
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      branchDisplayName: BRANCH_DISPLAY_NAME,
      floorPlanId: null,
      displayName: table.displayName,
      areaName: table.areaName,
      capacity: 4,
      status: "available",
      sortOrder: table.sortOrder,
      isActive: true,
      reservationAreaId: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      revision: 1,
    });
    console.log(`[provision_launch_tables] restaurantTables/${table.tableId}: created.`);
  } else {
    // Merge only the safe, descriptive fields — never touch `status`/
    // `activeTableSessionId`, which may legitimately be mid-session by the
    // time this script is re-run.
    await ref.set(
      {
        organizationId: ORGANIZATION_ID,
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        branchDisplayName: BRANCH_DISPLAY_NAME,
        displayName: table.displayName,
        areaName: table.areaName,
        sortOrder: table.sortOrder,
        isActive: true,
      },
      { merge: true },
    );
    console.log(`[provision_launch_tables] restaurantTables/${table.tableId}: already existed (descriptive fields refreshed, status untouched).`);
  }
}

async function ensureActiveQrCode(db, tableId) {
  const existing = await db
    .collection("tableQrCodes")
    .where("tableId", "==", tableId)
    .where("status", "==", "active")
    .limit(1)
    .get();

  if (!existing.empty) {
    const doc = existing.docs[0];
    console.log(`[provision_launch_tables] tableQrCodes for ${tableId}: active token already exists (${doc.id}), not re-minted.`);
    return doc.data().opaqueToken;
  }

  const token = mintOpaqueToken();
  const qrId = `qr-${tableId}`;
  await db.collection("tableQrCodes").doc(qrId).set({
    tableId,
    opaqueToken: token,
    status: "active",
    expiresAt: null,
    createdAt: new Date(),
  });
  console.log(`[provision_launch_tables] tableQrCodes/${qrId}: minted a new active token for ${tableId}.`);
  return token;
}

async function main() {
  const db = admin.firestore();

  const restaurantDoc = await db.collection("restaurants").doc(RESTAURANT_ID).get();
  if (!restaurantDoc.exists) {
    console.error(
      `[provision_launch_tables] restaurants/${RESTAURANT_ID} does not exist in "${PROJECT_ID}" — ` +
        "the canonical tenant (org-1/restaurant-1/branch-1) must already be provisioned first.",
    );
    process.exit(1);
  }

  const manifest = [];
  for (const table of TABLES) {
    await provisionTable(db, table);
    const token = await ensureActiveQrCode(db, table.tableId);
    manifest.push({
      tableId: table.tableId,
      displayName: table.displayName,
      areaName: table.areaName,
      opaqueToken: token,
    });
  }

  const __dirname = dirname(fileURLToPath(import.meta.url));
  const outDir = join(__dirname, "data");
  mkdirSync(outDir, { recursive: true });
  const outPath = join(outDir, "launch_table_qr_manifest.json");
  writeFileSync(outPath, JSON.stringify({ projectId: PROJECT_ID, tables: manifest }, null, 2));
  console.log(`[provision_launch_tables] wrote manifest: ${outPath}`);
  console.log(`[provision_launch_tables] done — ${manifest.length} tables provisioned in "${PROJECT_ID}".`);

  await app.delete();
}

main().catch((error) => {
  console.error("[provision_launch_tables] failed:", error);
  process.exitCode = 1;
});
