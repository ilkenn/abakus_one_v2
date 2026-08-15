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
class ChannelPricingPolicy {
  const ChannelPricingPolicy({
    this.channelDefaultAdjustments = const {},
    this.categoryOverrides = const {},
  });

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
