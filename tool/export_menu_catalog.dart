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
        // The real menu's fixed dishes carry no modifier/option structure
        // (AbakusMenuCatalog's own doc comment) and no product ever
        // configures a channelPriceOverrides entry today — both
        // empty/absent here is a faithful export, not a simplification.
        'modifierGroups': <Object?>[],
        'channelPriceOverrides': <String, Object?>{},
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
    },
  };

  const outputPath = 'functions/scripts/data/menu_catalog_export.json';
  File(outputPath).createSync(recursive: true);
  File(outputPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(export),
  );

  stderr.writeln(
    '[export_menu_catalog] wrote $outputPath — '
    '${categories.length} categories, ${products.length} products, '
    '${bowlIngredients.length} bowl ingredients, '
    '${channelDefaultAdjustments.length} channel default adjustment(s).',
  );
}
