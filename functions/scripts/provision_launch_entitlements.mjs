// 2026-10-29 — launch entitlement provisioning.
//
// `requireModuleEntitlement` (`functions/src/entitlementAdmin.ts`) fails
// closed with "Module \"<module>\" is not entitled for this organization"
// whenever no `entitlements/{organizationId}_organization_{organizationId}_
// {module}` document exists at all — confirmed by reading that function
// directly, not guessed. Entitlements are "entirely platform-controlled"
// (`entitlementAdmin.ts`'s own doc comment) — `firestore.rules` has no
// client writer for this collection at all (`allow write: if false`), and
// the one real writer callable (`grantEntitlement`) requires
// `requirePlatformMember`, a Platform Owner/Administrator identity, not a
// tenant admin like the account actually hitting this error. Writing
// directly via the Admin SDK is the same one-time-provisioning pattern this
// session already used for `provision_launch_tables.mjs`.
//
// SAFETY: requires an explicit `--project` matching an allow-listed real
// project id, and real Admin SDK credentials via
// `GOOGLE_APPLICATION_CREDENTIALS`. Idempotent — `.set()`-based upsert on
// `entitlementAdmin.ts`'s own deterministic id.
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node scripts/provision_launch_entitlements.mjs --project abakus-one-staging

import admin from "firebase-admin";

// 2026-11-13: + "abakus-one-dev" for the real-device test (docs/courier_pool_device_test.md).
const ALLOWED_PROJECT_IDS = new Set(["abakus-one-dev", "abakus-one-staging", "abakusone"]);

const projectArgIndex = process.argv.indexOf("--project");
const PROJECT_ID = projectArgIndex !== -1 ? process.argv[projectArgIndex + 1] : null;

if (!PROJECT_ID || !ALLOWED_PROJECT_IDS.has(PROJECT_ID)) {
  console.error(
    "[provision_launch_entitlements] --project is required and must be one of: " +
      `${[...ALLOWED_PROJECT_IDS].join(", ")}. Got: ${PROJECT_ID ?? "(none)"}.`,
  );
  process.exit(1);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error(
    "[provision_launch_entitlements] GOOGLE_APPLICATION_CREDENTIALS is not set — " +
      "point it at a real service-account key for this project before running.",
  );
  process.exit(1);
}

const ORGANIZATION_ID = "org-1";
// pos/kds unblock the Windows Admin app's POS tab and real KDS board
// (trustedDevice.ts's device-registration capability check); qrMenu is the
// dine-in QR ordering surface itself — granted alongside since it is the
// other half of the same Saturday launch flow.
// The dev project also gets "courier" so the Paket Servis / Kurye screens
// (Faz 3-4) can be device-tested; staging and production keep the launch set.
const MODULES = PROJECT_ID === "abakus-one-dev"
  ? ["pos", "kds", "qrMenu", "courier"]
  : ["pos", "kds", "qrMenu"];

function entitlementId(organizationId, scopeType, scopeId, module) {
  return `${organizationId}_${scopeType}_${scopeId}_${module}`;
}

const app = admin.initializeApp({ projectId: PROJECT_ID });

async function main() {
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();

  for (const module of MODULES) {
    const id = entitlementId(ORGANIZATION_ID, "organization", ORGANIZATION_ID, module);
    const ref = db.collection("entitlements").doc(id);
    const existing = await ref.get();
    if (existing.exists) {
      console.log(
        `[provision_launch_entitlements] ${id}: already exists (status: ${existing.data().status}), not overwritten.`,
      );
      continue;
    }
    await ref.set({
      organizationId: ORGANIZATION_ID,
      scopeType: "organization",
      scopeId: ORGANIZATION_ID,
      module,
      status: "active",
      contractStartsAt: null,
      contractEndsAt: null,
      graceStartedAt: null,
      graceEndsAt: null,
      postGraceDisabledModules: [],
      grantedByPlatformUid: "launch-seed-script-2026-10-29",
      grantedAt: now,
      updatedAt: now,
      version: 1,
    });
    console.log(`[provision_launch_entitlements] ${id}: created (status: active).`);
  }

  console.log(`[provision_launch_entitlements] done — project "${PROJECT_ID}".`);
  await app.delete();
}

main().catch((error) => {
  console.error("[provision_launch_entitlements] failed:", error);
  process.exitCode = 1;
});
