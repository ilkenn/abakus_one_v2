import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/models/order_channel.dart';

/// A frozen snapshot of every channel-level default adjustment and
/// category-level override currently configured — what
/// `ChannelPriceResolver` actually resolves a price against.
///
/// A channel absent from [channelDefaultAdjustments] resolves to a zero
/// adjustment (existing dine-in/delivery pricing is untouched by this
/// engine until a policy explicitly configures it) — see
/// [defaultAdjustmentFor]. A `(channel, categoryId)` pair present in
/// [categoryOverrides] always wins over the channel's own default for that
/// category.
///
/// Immutable by design — `ChannelPricingPolicyRepository` is the mutable,
/// admin-editable side; every value read through here is a stable point in
/// time, the same "policy snapshot, not a live reference" shape
/// `TaxPolicy`/`ChannelOperationPolicy` already establish.
/// 2026-11-11 — product owner: a channel priced as a percentage of the
/// dine-in (Masa) price, each resulting price rounded half up to the
/// nearest [roundToMinorUnits] — Paket Servis = ×1.35, nearest 5 TL (450 TL
/// → 610 TL). Applied to the product price and to every paid modifier
/// separately. Mirrors `ChannelPriceMultiplierRule` (functions/src/
/// takeawayCatalog.ts) and `applyChannelPriceMultiplier`.
class ChannelPriceMultiplier {
  const ChannelPriceMultiplier({
    required this.multiplierBasisPoints,
    required this.roundToMinorUnits,
  });

  /// 13500 = ×1.35.
  final int multiplierBasisPoints;

  /// 500 = 5 TL.
  final int roundToMinorUnits;

  /// Integer-only, half-up rounding — never floating point.
  Money apply(Money amount) {
    final step = roundToMinorUnits;
    final scaled = amount.minorUnits * multiplierBasisPoints;
    final steps = (2 * scaled + 10000 * step) ~/ (2 * 10000 * step);
    return Money(steps * step, amount.currency);
  }
}

class ChannelPricingPolicy {
  const ChannelPricingPolicy({
    this.channelDefaultAdjustments = const {},
    this.categoryOverrides = const {},
    this.channelPriceMultipliers = const {},
  });

  /// 2026-11-11 — optional; a channel without one keeps the additive rules.
  final Map<OrderChannel, ChannelPriceMultiplier> channelPriceMultipliers;

  /// [amount] scaled by [channel]'s multiplier, or unchanged without one.
  Money applyMultiplier(OrderChannel channel, Money amount) =>
      channelPriceMultipliers[channel]?.apply(amount) ?? amount;

  /// Channel -> the adjustment applied to every product on that channel
  /// with no category override and no product-level override.
  final Map<OrderChannel, Money> channelDefaultAdjustments;

  /// Channel -> categoryId -> adjustment, taking priority over
  /// [channelDefaultAdjustments] for products in that category.
  final Map<OrderChannel, Map<String, Money>> categoryOverrides;

  /// The adjustment for [categoryId] on [channel]: its category override if
  /// one is configured, else the channel's own default, else zero (in
  /// [currency]) — a channel/category this policy has never heard of never
  /// changes a product's price.
  Money adjustmentFor(
    OrderChannel channel,
    String categoryId,
    Currency currency,
  ) {
    final categoryOverride = categoryOverrides[channel]?[categoryId];
    if (categoryOverride != null) return categoryOverride;
    return channelDefaultAdjustments[channel] ?? Money.zero(currency);
  }

  /// [channel]'s own default adjustment, ignoring any category override —
  /// what a category-less product resolves against. Used directly by
  /// `ChannelPriceResolver.resolveBowlUnitPrice`: Bowl Builder has no
  /// `MenuCategory` of its own (see `BowlBuilderIngredient`'s doc comment),
  /// so there is no per-category lookup to perform for it.
  Money defaultAdjustmentFor(OrderChannel channel, Currency currency) {
    return channelDefaultAdjustments[channel] ?? Money.zero(currency);
  }
}
