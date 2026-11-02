import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requirePlatformMember } from "./platformAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { migrateCanonicalCatalog, type CatalogExport } from "./catalogMigration";
// `resolveJsonModule` (tsconfig.json) + this file living under `src/data/`
// (not `scripts/data/`, which is outside `rootDir` and would fail the
// build) — see `tool/export_menu_catalog.dart`'s own doc comment on why
// the export tool writes two copies of the same bytes.
import catalogExportJson from "./data/menu_catalog_export.json";

/**
 * 2026-10-30 — the real, key-free alternative to running
 * `scripts/migrate_canonical_catalog_to_project.mjs` by hand with a
 * downloaded service-account key. A deployed Cloud Function already runs
 * under its own Admin SDK identity (the function's own service account,
 * provisioned automatically by Firebase at deploy time) — no key file is
 * ever downloaded, held, or passed around for this to work. The only
 * credential-shaped action left is deploying this function itself
 * (`firebase deploy --only functions:syncCanonicalCatalog`), an ordinary
 * deployment, not a database-credentials exposure.
 *
 * The embedded `catalogExportJson` is a point-in-time snapshot (written by
 * `dart run tool/export_menu_catalog.dart`, committed to the repo like any
 * other generated artifact) — calling this re-deploys whatever the Dart
 * catalog looked like at the last export, not a live read of it. Re-run
 * the export + redeploy this function any time the Dart catalog changes,
 * then call this again; `migrateCanonicalCatalog` is `.set()`-based upsert
 * on deterministic ids, so repeat calls are safe.
 *
 * Gated by `requirePlatformMember` (not a per-organization permission) —
 * mirrors `entitlementAdmin.ts`'s own reasoning: syncing the canonical
 * catalog is a platform-operations action, not a tenant-manager one.
 * `organizationId`/`restaurantId` are still caller-supplied (not
 * hardcoded) so this isn't locked to one tenant, but the caller must
 * already be a genuine platform member to invoke it at all.
 */
export const syncCanonicalCatalog = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request: CallableRequest) => {
    requirePlatformMember(request);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const organizationId = requireString(data.organizationId, "organizationId");
    const restaurantId = requireString(data.restaurantId, "restaurantId");

    const db = getFirestore();
    const result = await migrateCanonicalCatalog(
      db,
      catalogExportJson as unknown as CatalogExport,
      { organizationId, restaurantId },
    );

    return {
      categoriesWritten: result.categoriesWritten,
      productsWritten: result.productsWritten,
      ingredientsWritten: result.ingredientsWritten,
      channelPricingPolicyWritten: result.channelPricingPolicyWritten,
      exportedAt:
        typeof (catalogExportJson as Record<string, unknown>).exportedAt === "string"
          ? (catalogExportJson as Record<string, unknown>).exportedAt
          : null,
    };
  },
);

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}
