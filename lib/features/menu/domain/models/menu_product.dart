import '../../../orders/domain/models/order_channel.dart';
import '../pricing/channel_price_rule.dart';
import 'modifier_group.dart';
import 'product_nutrition.dart';

/// A sellable menu item.
///
/// [imageKey] is a slug (not a file path) resolved to an actual asset via
/// `MenuImageResolver` — see `docs/menu_experience_architecture.md`. Keeping
/// it as a slug rather than a path means this model never hardcodes
/// `assets/images/...` anywhere, and a product whose image doesn't exist
/// yet simply resolves to a placeholder instead of a broken path.
class MenuProduct {
  final String id;
  final String categoryId;
  final String name;
  final String description;
  final double basePrice;
  final String imageKey;
  final List<ModifierGroup> modifierGroups;
  final ProductNutrition? nutrition;
  final bool isAvailable;

  /// Allergens this dish contains (e.g. `gluten`, `süt`, `yumurta`) — plain
  /// Turkish text, not an enum: the 2026-10 PDF menu refresh lists these
  /// per-dish in free form, and there is no fixed, codebase-wide allergen
  /// vocabulary to constrain it to. Empty for every product where the
  /// source didn't list one — never inferred or guessed from the
  /// ingredients in [description].
  final List<String> allergens;

  /// The dish's stated portion size, exactly as the source menu states it
  /// — `'150g'`, `'120-150g'`, `'4 adet'`, `'6 adet'`. Deliberately a
  /// string, not an `int` gram count: several real dishes are portioned by
  /// piece count or a range, which an `int` can't represent without
  /// inventing false precision. `null` where the source menu states none.
  final String? portionLabel;

  /// Mirrors the real menu's "Çok Satanlar" (best sellers) highlight — the
  /// real site cross-lists these products as a featured filter rather than
  /// a distinct category with its own items, so it's modeled here as a
  /// flag on the product, not a duplicate `MenuCategory`/product entry.
  final bool isFeatured;

  /// This product's own, explicit price override per channel — resolved by
  /// `ChannelPriceResolver` ahead of `ChannelPricingPolicy`'s category/
  /// channel defaults. A channel absent from this map (the default for
  /// every existing product) behaves exactly like `UseChannelDefault`:
  /// [basePrice] plus whatever the policy's category/channel default
  /// resolves to (zero for a channel the policy has no rule for). Additive
  /// field — every product defined before this existed keeps its current
  /// price on every channel unchanged.
  final Map<OrderChannel, ChannelPriceRule> channelPriceOverrides;

  /// Explicit override for [removableIngredients] — set for a product
  /// whose standard-garnish list is a fixed, catalog-wide rule rather than
  /// something derivable from [description] (e.g. every Bowl product's
  /// "Mısır/Susamlı Çörekotlu Salatalık" — see
  /// `standard_modifier_groups.dart`'s `StandardModifierGroups
  /// .bowlRemovableIngredients`; "Mor Lahana Turşusu" was removed from
  /// that list 2026-10-30 to avoid duplicating the Turşu Hakkı group's own
  /// default option). `null` (the default for every product defined
  /// before this existed) falls back to parsing [description] — see
  /// [removableIngredients].
  final List<String>? removableIngredientsOverride;

  const MenuProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.basePrice,
    required this.imageKey,
    this.modifierGroups = const [],
    this.nutrition,
    this.isAvailable = true,
    this.isFeatured = false,
    this.channelPriceOverrides = const {},
    this.allergens = const [],
    this.portionLabel,
    this.removableIngredientsOverride,
  });

  /// The ingredient names a customer may toggle off ("İçinden Çıkar") for
  /// this product — [removableIngredientsOverride] when set, otherwise
  /// derived deterministically from [description] (split on `,`, trimmed,
  /// trailing `.` stripped) for every product whose description is
  /// genuinely a comma-separated ingredient list. Products with no
  /// description, or a narrative (non-list) description, resolve to an
  /// empty list — never a guessed/fabricated ingredient name — which the
  /// UI treats as "no İçinden Çıkar section for this product."
  List<String> get removableIngredients {
    final override = removableIngredientsOverride;
    if (override != null) return override;
    if (!description.contains(',')) return const [];
    return description
        .replaceAll(RegExp(r'\.+$'), '')
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  MenuProduct copyWith({
    String? id,
    String? categoryId,
    String? name,
    String? description,
    double? basePrice,
    String? imageKey,
    List<ModifierGroup>? modifierGroups,
    ProductNutrition? nutrition,
    bool? isAvailable,
    bool? isFeatured,
    Map<OrderChannel, ChannelPriceRule>? channelPriceOverrides,
    List<String>? allergens,
    String? portionLabel,
    List<String>? removableIngredientsOverride,
  }) {
    return MenuProduct(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      basePrice: basePrice ?? this.basePrice,
      imageKey: imageKey ?? this.imageKey,
      modifierGroups: modifierGroups ?? this.modifierGroups,
      nutrition: nutrition ?? this.nutrition,
      isAvailable: isAvailable ?? this.isAvailable,
      isFeatured: isFeatured ?? this.isFeatured,
      channelPriceOverrides:
          channelPriceOverrides ?? this.channelPriceOverrides,
      allergens: allergens ?? this.allergens,
      portionLabel: portionLabel ?? this.portionLabel,
      removableIngredientsOverride:
          removableIngredientsOverride ?? this.removableIngredientsOverride,
    );
  }
}
