import type { Firestore } from "firebase-admin/firestore";

/**
 * The single write-logic implementation behind
 * `scripts/migrate_canonical_catalog.mjs` — Faz D.3.1. Extracted into a
 * proper, testable TypeScript module (rather than living only inline in
 * the `.mjs` script) so this repository's real automated test suite
 * (`npm run test:emulator`) can exercise the exact same code path the
 * dev/production migration script runs, instead of a second,
 * independently-drifting re-implementation. The script itself
 * (`require`s this module's compiled output via `createRequire`, the
 * standard robust CJS-from-ESM interop, rather than relying on static
 * named-export analysis) does nothing but read the exported JSON file and
 * call [migrateCanonicalCatalog].
 *
 * Input shape mirrors `tool/export_menu_catalog.dart`'s own JSON output
 * exactly — see that script's doc comment for the full "Dart is the only
 * hand-authored source" sync strategy this module is the Firestore-side
 * half of. Faz D.3.1.1: the export/migration now also carries the real
 * `channelPricingPolicies/{restaurantId}` document (sourced from the same
 * Dart `InMemoryChannelPricingPolicyRepository` the rest of the app already
 * uses), closing the one remaining gap where `npm run seed:dev-all` left a
 * fully migrated catalog with no pricing policy to price it against.
 */

export interface CatalogExportCategory {
  id: string;
  name: string;
  sortOrder: number;
  isActive: boolean;
}

export interface CatalogExportProduct {
  id: string;
  categoryId: string;
  name: string;
  basePriceMinorUnits: number;
  isAvailable: boolean;
  modifierGroups: unknown[];
  channelPriceOverrides: Record<string, unknown>;
}

export interface CatalogExportIngredient {
  id: string;
  categoryId: string;
  name: string;
  priceMinorUnits: number;
  isAvailable: boolean;
}

export interface CatalogExportChannelPricingPolicy {
  channelDefaultAdjustments: Record<string, number>;
  categoryOverrides: Record<string, Record<string, number>>;
}

export interface CatalogExport {
  categories: CatalogExportCategory[];
  products: CatalogExportProduct[];
  bowlIngredients: CatalogExportIngredient[];
  channelPricingPolicy: CatalogExportChannelPricingPolicy;
}

export interface CatalogMigrationResult {
  categoriesWritten: number;
  productsWritten: number;
  ingredientsWritten: number;
  channelPricingPolicyWritten: boolean;
}

// Firestore batches cap at 500 writes — chunk defensively even though
// today's real catalog (79 products) is well under that.
const BATCH_SIZE = 400;

async function writeInBatches<T>(
  db: Firestore,
  items: T[],
  collectionName: string,
  toDocument: (item: T) => { id: string; data: Record<string, unknown> },
): Promise<number> {
  for (let i = 0; i < items.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const item of items.slice(i, i + BATCH_SIZE)) {
      const { id, data } = toDocument(item);
      batch.set(db.collection(collectionName).doc(id), data);
    }
    await batch.commit();
  }
  return items.length;
}

/**
 * Writes the exported catalog to Firestore — deterministic ids (the same
 * ids the Dart catalog itself already uses), `.set()`-based upsert
 * (idempotent: re-running with the same export never produces a
 * duplicate, only updates the same documents), scoped to one
 * organization/restaurant (this app's single seeded tenant today).
 */
export async function migrateCanonicalCatalog(
  db: Firestore,
  exportData: CatalogExport,
  scope: { organizationId: string; restaurantId: string },
): Promise<CatalogMigrationResult> {
  const categoriesWritten = await writeInBatches(
    db,
    exportData.categories,
    "menuCategories",
    (category) => ({
      id: category.id,
      data: {
        organizationId: scope.organizationId,
        restaurantId: scope.restaurantId,
        name: category.name,
        sortOrder: category.sortOrder,
        isActive: category.isActive,
      },
    }),
  );

  const productsWritten = await writeInBatches(
    db,
    exportData.products,
    "menuProducts",
    (product) => ({
      id: product.id,
      data: {
        organizationId: scope.organizationId,
        restaurantId: scope.restaurantId,
        categoryId: product.categoryId,
        name: product.name,
        basePriceMinorUnits: product.basePriceMinorUnits,
        isAvailable: product.isAvailable,
        modifierGroups: product.modifierGroups,
        channelPriceOverrides: product.channelPriceOverrides,
      },
    }),
  );

  const ingredientsWritten = await writeInBatches(
    db,
    exportData.bowlIngredients,
    "bowlIngredients",
    (ingredient) => ({
      id: ingredient.id,
      data: {
        organizationId: scope.organizationId,
        restaurantId: scope.restaurantId,
        categoryId: ingredient.categoryId,
        name: ingredient.name,
        priceMinorUnits: ingredient.priceMinorUnits,
        isAvailable: ingredient.isAvailable,
      },
    }),
  );

  // Faz D.3.1.1 — the channel pricing policy is migrated as part of the
  // same canonical catalog write, from the same export, rather than living
  // in a second, independent seed script (`seed_dev_catalog.mjs`'s own
  // hand-typed +20/+0 values, now superseded). One restaurant, one policy
  // document, `.set()`-based upsert — idempotent by the same construction
  // as every other write in this function.
  await db
    .collection("channelPricingPolicies")
    .doc(scope.restaurantId)
    .set({
      channelDefaultAdjustments: exportData.channelPricingPolicy.channelDefaultAdjustments,
      categoryOverrides: exportData.channelPricingPolicy.categoryOverrides,
    });

  return { categoriesWritten, productsWritten, ingredientsWritten, channelPricingPolicyWritten: true };
}
