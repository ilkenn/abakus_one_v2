# Real Menu, Premium Product Experience & Bowl Builder — Architecture

> Status: real Abaküs menu imported, product/modifier domain reused end-to-end, Bowl Builder
> implemented as a distinct feature on top of the same domain. No backend, networking, POS, QR
> ordering, kitchen, courier, or inventory work exists yet — this phase is UI + local state only.

## 1. Purpose

Replace the placeholder demo catalog with the real Abaküs Ortaköy menu, give products a premium
detail experience with a genuine (if currently empty, for real dishes) modifier system, and add a
"Kendi Bowlunu Yarat" builder that produces a fully custom bowl/salad using the same cart and
pricing machinery as every other product.

## 2. Menu source and provenance

The real menu was sourced from the live Abaküs Ortaköy site export at
`C:\Users\Mücahit\Desktop\restoran-sitemiz\menu.html`, which contains a structured `menuData`
object with categories, product names, Turkish descriptions, TRY prices, and image filenames. All
79 products were transcribed verbatim — no name, price, description, or category was invented,
reworded, or reordered. See `lib/features/menu/data/abakus_menu_catalog.dart`.

The real site's "Çok Satanlar" (best sellers) view is not a separate category — it is a curated
subset of existing products. Modeling it as a second category or duplicate product list would have
violated the "never duplicate products" rule, so it is instead a boolean `MenuProduct.isFeatured`
flag on the 8 affected products, consumed by `featuredMenuProductsProvider`.

Real-menu products carry no `modifierGroups` — every dish on the live site is a fixed composition
with no customer-facing customization. Modifier groups are a real, reusable domain capability
(`ModifierGroup`/`ModifierOption`), but on this import they are simply unused (`[]`). The
Bowl Builder is the one place in this phase where they are populated.

## 3. Domain model reuse

No new product/pricing concept was introduced. Everything is built from:

| Model | File | Role |
|---|---|---|
| `MenuCategory` | `lib/features/menu/domain/models/menu_category.dart` | One of the 7 real menu tabs. |
| `MenuProduct` | `lib/features/menu/domain/models/menu_product.dart` | A real dish or a Bowl Builder base price + name. |
| `ModifierGroup` / `ModifierOption` | `lib/features/menu/domain/models/modifier_group.dart`, `modifier_option.dart` | Reused unchanged by both `ProductDetailScreen` (real products with modifiers, when present) and Bowl Builder (every ingredient step). |
| `ProductNutrition` | `lib/features/menu/domain/models/product_nutrition.dart` | Optional; unset for the current real import (no nutrition data in the source), rendered only when present. |
| `SelectedModifier` | `lib/features/menu/domain/models/selected_modifier.dart` | The frozen, cart-facing record of one chosen option — produced identically by `ProductDetailScreen` and `BowlBuilderScreen`. |
| `CartItem` | `lib/features/cart/domain/models/cart_item.dart` | Single canonical cart line, now carrying `selectedModifiers` and `note` alongside the legacy fields it already had. |

`ModifierGroup.visibleChannels` reuses the existing `OrderChannel` enum (already used by
`OrderModel`) instead of inventing a parallel concept for "where can this option be offered."

## 4. Image resolution

`MenuImageResolver` (`lib/features/menu/domain/services/menu_image_resolver.dart`) is the single
place that maps a product's `imageKey` to a real bundled asset path. It holds an exact,
case-sensitive set of the 69 filenames actually present under `assets/images/menu/` (which is now
registered in `pubspec.yaml` — it previously was not, so none of these images could ever have
loaded). Resolution is strict-exact-match only; there is no fuzzy/best-guess matching, because a
wrong guess would silently show the wrong dish's photo. Any product whose `imageKey` isn't in that
set renders through `ProductImage` (`lib/shared/widgets/images/product_image.dart`) as an
icon-on-tinted-background placeholder instead.

### 4.1 Missing images

26 of the 79 real products have an `imageKey` that does not exactly match a bundled asset filename
— due to hyphenation differences, apostrophes, capitalization, translation, or the asset simply not
existing yet. These currently render as placeholders:

**Bowl (5):** `ton-ton-bowl`, `golden-harmony`, `chefs-fire`, `vegan-bowl`, `lokum-bowl`

**Salata (5):** `crispy-falafel-salad`, `ton-ton-salad`, `moms-chicken-salad`, `pineapple-salad`,
`lokum-salad`

**Wrap (2):** `mexico-chicken-wrap`, `ton-ton-wrap`

**Hamburger (2):** `double-chicken`, `swiss-mushroom-burger`

**Makarna (2):** `crispy-midye`, `fettucine-meatball-alfredo`

**Atıştırmalık (6, no source asset at all):** `truflu-patates`, `sogan-halkasi`, `citir-falafel`,
`cheddarli-patates-kizartmasi`, `citir-tavuk`, `patates-kizartmasi`

**İçecekler (4, no source asset at all):** `acili-ayran`, `naneli-ayran`, `eksili-ayran`,
`cocacola`

Most of the Bowl/Salata/Wrap/Hamburger/Makarna cases are near-misses (e.g. `ton-ton-bowl` vs. the
bundled `tonton-bowl`, `vegan-bowl` vs. bundled `Vegan-Bowl`, `chefs-fire` vs. bundled
`chef's-fire-bowl`) and would resolve immediately once either the product's `imageKey` or the
asset filename is corrected to match. The Atıştırmalık and İçecekler cases have no candidate asset
in `assets/images/menu/` at all and need new photos supplied. `MenuImageResolver.findMissingImageKeys`
computes this list programmatically from the live catalog — this section is a snapshot, not the
source of truth; re-run the resolver's test or call it directly after any catalog/asset change.

## 5. Bowl Builder

`lib/features/bowl_builder/` implements "Kendi Bowlunu / Salatanı Yarat" against the current
commercial model: a **430 TL starting price**, and 10 categories in a fixed order — Baz → Salata →
Protein → Turşu → Yan Ürün → Peynir → Meyve → Baklagil → Topping → Sos → Özet. Every category step
(all but Özet) shows **two** `ModifierGroup`s from `BowlBuilderCatalog`
(`lib/features/bowl_builder/data/bowl_builder_catalog.dart`) on the same screen: a "normal" group
covering that category's included selection right(s) (`bowlBuilderStepGroups`), and a paid "Extra"
group for anything beyond it (`bowlBuilderExtraGroupsByStep`) — both driven by the same maps, so
adding, removing, or reordering a category is a data change, not a new screen.

**No category is required.** The product has its own starting price, so a customer can add it to
the cart with zero selections. Selection *rights* are enforced by each normal group's
`selectionType`/`maxSelections` — single-select (max 1) for every category except Yan Ürün
(multiple, max 2). A single-select group makes a second normal pick structurally impossible: tapping
a different option in Protein *replaces* the current one rather than adding a second, which is what
"a second protein can't be chosen from the normal section" actually means in this UI — there's
nothing to separately "block." Yan Ürün's multiple-select group is the one place a normal pick can
be genuinely blocked (its `toggleMultiple` guard no-ops past `maxSelections`), which is why its
`AppSectionHeader` subtitle turns into an explicit "hakkınız doldu, Extra bölümünü kullanın" message
once the quota is filled.

Ingredient data, by provenance:
- **Real, given directly**: 430 TL; every category's free/premium option set; every premium delta
  named explicitly (Makarna +20; Baby Ispanak/Çoban Salata +30; protein tiers
  +40/+70/+150/+150/+250/+300; Soğan Turşusu/Jalapeño +20; side-dish tiers +20/+30/+40/+50).
- **Real, mined from `AbakusMenuCatalog` descriptions**: the four "diğer tavuk çeşitleri" (Soya
  Soslu Tavuk, Tatlı Ekşi Tavuk, Köri Soslu Tavuk, Tatlı Acı Tavuk — from Asian Chicken Bowl, Sweet
  Sour Bowl, Golden Harmony, Chef's Fire); the fruit list (Ananas, Yeşil Elma, Nar, Muz, Ahududu,
  Böğürtlen); Havuç/Kırmızı Soğan/Kapya Biber/Mor Lahana as the four priced side dishes (the
  tier-to-item assignment is this project's own temporary judgment call, not given). `Baklagil` has
  exactly one real option ("Meksika Fasulyesi") because no other legume is named anywhere in the
  real menu source — honestly limited to what the source contains rather than padded out.
- **Temporary placeholder pricing**: every `extraFooGroup` price. Where the category already has a
  real premium delta (Protein, Yan Ürün), that same delta is reused for a second unit via Extra;
  where the normal pick is free with no real "second unit" price (Baz, Salata, Turşu, Peynir, Meyve,
  Baklagil, Topping, Sos), a flat per-category surcharge constant is used instead (`kExtraBaseSurcharge`,
  `kExtraSaladSurcharge`, etc., all defined once at the top of `BowlBuilderCatalog` — the UI never
  hardcodes a price). Peynir/Topping's Extra prices specifically reuse this project's own earlier
  temporary per-item prices from before those categories became "free on first pick." Ton Balığı
  exists only in `extraProteinGroup` — it's real but doesn't fit any of the given protein tiers, so
  it isn't offered as an included choice.

Selections persist across back-navigation (state lives in `BowlBuilderState`, not per-step widget
state), pricing recalculates live and is shown continuously — a running total is visible on every
category step, not only on the summary — via `bowlBuilderTotalPriceProvider` (unit price:
`kBowlBuilderStartingPrice` + every selected option's extra price, normal and Extra groups alike,
computed once over `bowlBuilderAllGroups`) and `bowlBuilderGrandTotalProvider` (unit price ×
quantity). The summary step also carries a quantity stepper and an order note
(`BowlBuilderState.quantity`/`.note`, mutated only through `BowlBuilderNotifier`, mirroring how
`ProductDetailScreen` handles the same concepts locally). Completing the flow adds one `CartItem`
via the same `cartProvider.notifier.addToCart` call used everywhere else, passing the *starting*
price, `selectedModifiers`, and `quantity` separately so `CartItem.unitPrice`/`totalRowPrice` do the
extras-summing and quantity-multiplying exactly once — a prior version of `_addToCart` passed the
already-summed total *and* `selectedModifiers` together, which silently double-counted every priced
extra once it reached the cart; this is covered by dedicated tests in `bowl_builder_screen_test.dart`
asserting exact expected totals against the real pricing tiers.

## 6. Product Detail and Cart integration

`ProductDetailScreen` takes a `MenuProduct` directly (no more ad-hoc `Map<String, String>`). It
renders whatever `modifierGroups` the product has — currently none for real-menu products, so the
screen degrades to name/price/description/note/quantity for them today, but the same required/
optional/min/max validation, dynamic pricing, and modifier rendering used by Bowl Builder is fully
wired and exercised by tests using a fixture product with modifier groups.

`CartItem` (`lib/features/cart/domain/models/cart_item.dart`) is now the single cart line model —
the inline `CartItemModel` previously duplicated inside `cart_provider.dart` was deleted. It carries
`selectedModifiers` and `note` in addition to the legacy protein/sauce/removed/extra-ingredient
fields kept for backward compatibility with pre-existing screens. `unitPrice` folds in every
selected modifier's `extraPrice`; the cart's merge/dedup key includes sorted modifier option ids
and the note, so two otherwise-identical line items with different customizations never collapse
into one.

## 7. Deferred / out of scope

- Backend, Firebase, networking, POS, QR ordering, kitchen, courier, inventory — none of this
  phase touches any of them.
- Serialization (`toJson`/`fromJson`) for any menu/bowl-builder model — same rationale as the
  Table QR phase: no networking dependency exists yet to justify it.
- `HomeMockData` (`lib/features/home/presentation/data/mock_data.dart`) still backs the
  "Son Siparişin" (reorder-simulation) section on Home — intentionally untouched, out of scope for
  a menu-catalog phase, and not menu data in the first place.
- The 26 missing images listed in §4.1 — either the `imageKey` values, the asset filenames, or (for
  Atıştırmalık/İçecekler) the assets themselves need to be supplied; today they correctly fall back
  to placeholders rather than showing a wrong photo.
- Real pricing for every Bowl Builder `extraFooGroup` (Extra Baz/Salata/Protein/Turşu/Yan
  Ürün/Peynir/Meyve/Baklagil/Topping/Sos) — the starting price (430 TL) and every normal-group
  premium delta are now real, given directly, but every "second unit" surcharge is still a
  documented temporary placeholder isolated in `BowlBuilderCatalog`'s `kExtra*Surcharge` constants
  and per-item Extra prices.
- No fabricated "loading" state on Menu/Product Detail/Bowl Builder: catalog data is a compiled-in
  `List<MenuProduct>`/`List<ModifierGroup>`, read synchronously — there is no async boundary to show
  a spinner for, and inventing one would be a dishonest loading state for data that's already there.
  `ProductImage` does fade in via `Image.asset`'s `frameBuilder` (a real, if brief, asset-decode
  boundary), which is the one legitimate "loading" moment in this feature today. A genuine loading
  state becomes relevant once product data or images come from a network/backend, at which point it
  belongs on that boundary, not simulated ahead of time.
