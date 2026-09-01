// AP-4 Wave E — dev/emulator seed for org-1's `pos` module entitlement.
// `entitlements` has no tenant-scoped writer (`entitlementAdmin.ts`'s own
// doc comment: only `requirePlatformMember` can grant one, by design —
// "Tenant Admin kendisine entitlement veremez"), and the Platform Owner
// bootstrap path (`bootstrap_platform_owner.mjs`) is a deliberately
// out-of-band, manual, real-credential-gated script. For local Flutter
// integration-test seeding specifically, writing the entitlement document
// directly via the Admin SDK is the same mechanism this codebase's own
// Node backend test suite already uses for this exact document
// (`seedTenant()` helpers throughout `functions/src/test/*.test.ts`) —
// not a new pattern, just applied from a standalone script instead of a
// test file's own inline fixture.
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set.
import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[seed_dev_pos_entitlement] FIRESTORE_EMULATOR_HOST is not set — " +
      "refusing to run against anything but the local emulator.",
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const ORGANIZATION_ID = "org-1";

const app = admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

const docId = `${ORGANIZATION_ID}_organization_${ORGANIZATION_ID}_pos`;
await db.collection("entitlements").doc(docId).set({
  organizationId: ORGANIZATION_ID,
  scopeType: "organization",
  scopeId: ORGANIZATION_ID,
  module: "pos",
  status: "active",
  version: 1,
  contractStartsAt: null,
  contractEndsAt: null,
});
console.log(`[seed_dev_pos_entitlement] entitlements/${docId}: provisioned (pos, active).`);

await app.delete();
