// Faz D.3.1 — canonical catalog export tool.
//
// Serializes the real, compiled-in Dart menu/Bowl Builder catalogs
// (`AbakusMenuCatalog`, `LocalBowlBuilderCatalogRepository`) to JSON —
// the one generated artifact `functions/scripts/migrate_canonical_catalog.mjs`
// reads to populate the Firestore-canonical `menuProducts`/
// `bowlIngredients` collections.
//
// **This is the "single source" sync strategy** (Faz D.3.1 §3): Dart
// remains the only place a product/ingredient/price is hand-authored.
// This script never hand-copies catalog data itself — it reads the same
// `AbakusMenuCatalog`/`LocalBowlBuilderCatalogRepository` constants the
// Flutter app itself displays from, and turns them into data. Re-run this
// script (then the migration script) any time the Dart catalog changes;
// nothing about the catalog is ever typed a second time by a human.
//
// Pure Dart, no Flutter SDK dependency (`AbakusMenuCatalog`/
// `BowlBuilderCatalogRepository` and everything they import are plain
// Dart classes) — runs via `dart run tool/export_menu_catalog.dart`, no
// `flutter run`/emulator/device needed.
//
// Money: `MenuProduct.basePrice`/`BowlBuilderIngredient.price` are legacy
// `double` TRY amounts (see `Money.fromLegacyDoubleTry`'s own doc comment
// on why that boundary type still exists) — converted here to integer
// minor units (kuruş) via the exact same `(amountInTry * 100).round()`
// rule `Money.fromLegacyDoubleTry` itself uses, so this export loses no
// precision relative to what the Flutter app already displays.

import 'dart:convert';
import 'dart:io';

import 'package:abakus_one_v2/features/menu/data/abakus_menu_catalog.dart';
import 'package:abakus_one_v2/features/bowl_builder/data/bowl_builder_catalog.dart';
import 'package:abakus_one_v2/features/menu/data/channel_pricing_policy_repository.dart';

int toMinorUnits(double amountInTry) => (amountInTry * 100).round();

Future<void> main() async {
  final categories = [
    for (final category in AbakusMenuCatalog.categories)
      {
        'id': category.id,
        'name': category.name,
        'sortOrder': category.sortOrder,
        'isActive': category.isActive,
        // KDS station-based routing (2026-09-21) — `null` when unset,
        // matching `MenuCategory.defaultStation`'s own "no override,
        // falls back to shared" semantics.
        'defaultStation': category.defaultStation?.name,
      },
  ];

  final products = [
    for (final product in AbakusMenuCatalog.products)
      {
        'id': product.id,
        'categoryId': product.categoryId,
        'name': product.name,
        'basePriceMinorUnits': toMinorUnits(product.basePrice),
        'isAvailable': product.isAvailable,
        'isFeatured': product.isFeatured,
        // 2026-10-30 product-configurator — `AbakusMenuCatalog.products`
        // (not `_rawProducts`) now layers real modifier groups onto Bowl/
        // Burger/Wrap/every product (`standard_modifier_groups.dart`), so
        // this must actually serialize them — a hardcoded empty array here
        // would silently make every one of those groups invisible to
        // `resolveProductModifiers` server-side, rejecting every real
        // order that selects one. No product ever configures a
        // channelPriceOverrides entry today, so that one stays empty.
        'modifierGroups': [
          for (final group in product.modifierGroups)
            {
              'id': group.id,
              'name': group.name,
              'selectionType': group.selectionType.name,
              'isRequired': group.isRequired,
              'minSelections': group.minSelections,
              'maxSelections': group.maxSelections,
              'options': [
                for (final option in group.options)
                  {
                    'id': option.id,
                    'name': option.name,
                    'extraPriceMinorUnits': toMinorUnits(option.extraPrice),
                    'isAvailable': option.isAvailable,
                  },
              ],
            },
        ],
        'channelPriceOverrides': <String, Object?>{},
        // 2026-10-28 PDF menu refresh.
        'allergens': product.allergens,
        'portionLabel': product.portionLabel,
        // ADR-067 (2026-11-09) — `kilogram` makes `basePriceMinorUnits` a
        // per-kg price, priced server-side by `weightGrams`.
        'saleUnit': product.saleUnit.name,
      },
  ];

  const bowlCatalog = LocalBowlBuilderCatalogRepository();
  final bowlIngredients = <Map<String, Object?>>[];
  for (final category in bowlCatalog.categories) {
    for (final ingredient in bowlCatalog.ingredientsFor(category.id)) {
      bowlIngredients.add({
        'id': ingredient.id,
        'categoryId': ingredient.categoryId,
        'name': ingredient.name,
        'priceMinorUnits': toMinorUnits(ingredient.price),
        'isAvailable': ingredient.isAvailable,
        'sortOrder': ingredient.sortOrder,
      });
    }
  }

  // Faz D.3.1.1 — the same "Dart is the only hand-authored source" rule
  // applies to the channel pricing policy, not just the catalog: read the
  // real `InMemoryChannelPricingPolicyRepository` (the one already backing
  // `ChannelPriceResolver` throughout the app, `docs/business_rules.md`
  // BR-PRICE-004) rather than hand-typing the same +20/+0 numbers a second
  // time in a seed script. Enum keys serialize via `OrderChannel.name`/
  // `.name` (e.g. `takeaway`), matching the string-keyed map shape
  // `submitTakeawayOrder`'s `channelPricingPolicies/{restaurantId}` reader
  // already expects.
  final policy = await InMemoryChannelPricingPolicyRepository().current();
  final channelDefaultAdjustments = {
    for (final entry in policy.channelDefaultAdjustments.entries)
      entry.key.name: entry.value.minorUnits,
  };
  final categoryOverrides = {
    for (final channelEntry in policy.categoryOverrides.entries)
      channelEntry.key.name: {
        for (final categoryEntry in channelEntry.value.entries)
          categoryEntry.key: categoryEntry.value.minorUnits,
      },
  };

  final export = {
    'exportedAt': DateTime.now().toIso8601String(),
    'categories': categories,
    'products': products,
    'bowlIngredients': bowlIngredients,
    'channelPricingPolicy': {
      'channelDefaultAdjustments': channelDefaultAdjustments,
      'categoryOverrides': categoryOverrides,
      // 2026-11-11 — Paket Servis ×1.35, nearest 5 TL.
      'channelPriceMultipliers': {
        for (final entry in policy.channelPriceMultipliers.entries)
          entry.key.name: {
            'multiplierBasisPoints': entry.value.multiplierBasisPoints,
            'roundToMinorUnits': entry.value.roundToMinorUnits,
          },
      },
    },
  };

  final encoded = const JsonEncoder.withIndent('  ').convert(export);

  const outputPath = 'functions/scripts/data/menu_catalog_export.json';
  File(outputPath).createSync(recursive: true);
  File(outputPath).writeAsStringSync(encoded);

  // 2026-10-30 — a second copy under `functions/src/data/` so the
  // deployed `syncCanonicalCatalog` callable (`functions/src/
  // syncCanonicalCatalog.ts`) can `import` it directly: `tsconfig.json`'s
  // `rootDir: "src"` means a JSON import outside `src/` fails the build,
  // and relying on a loose file surviving Cloud Functions' own deployment
  // bundling (uncertain, undocumented) would be a silent, hard-to-diagnose
  // way for a real deploy to ship with stale/missing catalog data. Same
  // bytes, two paths — one Dart run keeps both in sync, nothing is
  // hand-typed twice.
  const srcOutputPath = 'functions/src/data/menu_catalog_export.json';
  File(srcOutputPath).createSync(recursive: true);
  File(srcOutputPath).writeAsStringSync(encoded);

  stderr.writeln(
    '[export_menu_catalog] wrote $outputPath and $srcOutputPath — '
    '${categories.length} categories, ${products.length} products, '
    '${bowlIngredients.length} bowl ingredients, '
    '${channelDefaultAdjustments.length} channel default adjustment(s).',
  );
}
