// Rezervasyon — Faz R.1A — reusable dev/emulator reservation policy + area
// seed. Writes a real `reservationPolicies/branch-1` document and two real
// `reservationAreas` documents ("Bahçe"/"İç Mekân"), bound to this app's
// real canonical tenant chain (org-1 -> restaurant-1 -> branch-1 — the same
// chain `seed_dev_tenant.mjs` provisions). Requires that chain to already
// exist; run `npm run seed:dev-tenant` first.
//
// Mirrors `seed_dev_takeaway_qr.mjs`'s own reasoning exactly:
// `reservationPolicies`/`reservationAreas` have no dedicated `provision*`
// callable and no client-write path at all (`firestore.rules`'s fail-closed
// catch-all covers both — see that file's own Faz R.1A comment) — the
// Admin SDK is the only, correct way anything ever writes to them. This
// script does not bypass any authorization/validation logic that exists
// elsewhere, because none exists to bypass.
//
// Policy values match `docs/decisions.md` ADR-027 Faz R.0.7 §10's final,
// locked seed: bookingHorizonDays=60, slotIntervalMinutes=15,
// reservationDurationMinutes=90, maxPartySize=12,
// customerCancellationCutoffMinutes=60, restaurantResponseTimeoutMinutes=120,
// proposalHoldMinutes=15. `minimumAdvanceMinutes` is deliberately absent —
// it is `submitReservation.ts`'s own `MINIMUM_ADVANCE_MINUTES` platform
// constant (30), never a policy field (Faz R.0.7 §1).
//
// Area capacity values (garden=40, indoor=30) are dev-seed placeholders
// only — no real business capacity decision has been made for Abaküs's own
// branch-1 areas; picked to be plausible restaurant-scale numbers for local
// testing, not derived from any real floor plan.
//
// Safe to re-run any time — fixed document ids, `.set()` upserts rather
// than creating duplicates.
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set. Run via:
//
//   cd functions
//   firebase emulators:exec --only firestore,functions,auth \
//     "node scripts/seed_dev_tenant.mjs && node scripts/seed_dev_reservation.mjs"

import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[seed_dev_reservation] FIRESTORE_EMULATOR_HOST is not set — refusing " +
      "to run against anything but the local emulator suite. Run via " +
      '`firebase emulators:exec --only firestore,functions,auth ' +
      '"node scripts/seed_dev_tenant.mjs && node scripts/seed_dev_reservation.mjs"`.',
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const ORGANIZATION_ID = "org-1";
const RESTAURANT_ID = "restaurant-1";
const BRANCH_ID = "branch-1";

const app = admin.initializeApp({ projectId: PROJECT_ID });

async function main() {
  const db = admin.firestore();

  const branchDoc = await db.collection("branches").doc(BRANCH_ID).get();
  if (!branchDoc.exists) {
    console.error(
      `[seed_dev_reservation] branches/${BRANCH_ID} does not exist — run ` +
        "`npm run seed:dev-tenant` first to provision the canonical " +
        "org-1 -> restaurant-1 -> branch-1 chain.",
    );
    process.exit(1);
  }

  const now = new Date();

  await db.collection("reservationPolicies").doc(BRANCH_ID).set({
    organizationId: ORGANIZATION_ID,
    restaurantId: RESTAURANT_ID,
    branchId: BRANCH_ID,
    enabled: true,
    bookingHorizonDays: 60,
    slotIntervalMinutes: 15,
    reservationDurationMinutes: 90,
    maxPartySize: 12,
    customerCancellationCutoffMinutes: 60,
    restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15,
    timezone: "Europe/Istanbul",
    createdAt: now,
    updatedAt: now,
    revision: 1,
  });
  console.log(`[seed_dev_reservation] reservationPolicies/${BRANCH_ID}: provisioned.`);

  const areas = [
    { id: "garden", displayName: "Bahçe", sortOrder: 1, capacity: 40 },
    { id: "indoor", displayName: "İç Mekân", sortOrder: 2, capacity: 30 },
  ];
  for (const area of areas) {
    await db.collection("reservationAreas").doc(area.id).set({
      organizationId: ORGANIZATION_ID,
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      displayName: area.displayName,
      sortOrder: area.sortOrder,
      isActive: true,
      capacity: area.capacity,
      createdAt: now,
      updatedAt: now,
      revision: 1,
    });
    console.log(`[seed_dev_reservation] reservationAreas/${area.id}: provisioned ("${area.displayName}").`);
  }

  // Faz R.2 — PLACEHOLDER operating hours only. Every day 11:00-23:00,
  // single interval, no date overrides. This is NOT a real Abaküs business
  // decision — no real branch-1 operating hours have been provided as of
  // this seed's writing. Stands in only so local development/testing isn't
  // permanently blocked by the "missing document = closed every day"
  // fail-safe default (`branchOperatingHours.ts`). Replace via the future
  // R.3 admin editing UI (or a direct data update) once real hours are
  // known — never treat this as authoritative.
  const dailyWindow = [{ startMinute: 11 * 60, endMinute: 23 * 60 }];
  await db.collection("branchOperatingHours").doc(BRANCH_ID).set({
    branchId: BRANCH_ID,
    organizationId: ORGANIZATION_ID,
    restaurantId: RESTAURANT_ID,
    weeklySchedule: {
      monday: dailyWindow,
      tuesday: dailyWindow,
      wednesday: dailyWindow,
      thursday: dailyWindow,
      friday: dailyWindow,
      saturday: dailyWindow,
      sunday: dailyWindow,
    },
    dateOverrides: {},
    updatedAt: now,
    updatedByStaffId: null,
    revision: 1,
  });
  console.log(
    `[seed_dev_reservation] branchOperatingHours/${BRANCH_ID}: provisioned (PLACEHOLDER 11:00-23:00 daily — not real business hours).`,
  );

  await app.delete();
}

main().catch((error) => {
  console.error("[seed_dev_reservation] failed:", error);
  process.exitCode = 1;
});
