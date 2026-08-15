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
  });

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
    );
  }
}
