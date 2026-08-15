import '../../../../shared/models/money.dart';

/// A product's own, explicit override of how its price behaves on one
/// specific `OrderChannel` — resolved by `ChannelPriceResolver`, layered on
/// top of `ChannelPricingPolicy`'s category/channel defaults.
///
/// `MenuProduct.channelPriceOverrides` maps a channel to at most one of
/// these; a channel with no entry behaves exactly like [UseChannelDefault]
/// — additive, so every product defined before this existed keeps its
/// current price on every channel unchanged.
sealed class ChannelPriceRule {
  const ChannelPriceRule();
}

/// No product-level override — resolve from `ChannelPricingPolicy`'s
/// category override or channel default instead. Equivalent to the channel
/// simply being absent from `MenuProduct.channelPriceOverrides`; exists so
/// a caller can *explicitly* record "yes, we considered this channel, the
/// answer is the default" rather than that being indistinguishable from
/// "never configured."
final class UseChannelDefault extends ChannelPriceRule {
  const UseChannelDefault();

  @override
  bool operator ==(Object other) => other is UseChannelDefault;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// This product's price on the channel is its `basePrice` plus a fixed
/// [adjustment] (which may be negative) — e.g. "+20 TL", overriding
/// whatever the category default would have produced.
final class ChannelFixedAdjustment extends ChannelPriceRule {
  const ChannelFixedAdjustment(this.adjustment);

  final Money adjustment;

  @override
  bool operator ==(Object other) =>
      other is ChannelFixedAdjustment && other.adjustment == adjustment;

  @override
  int get hashCode => adjustment.hashCode;
}

/// This product's price on the channel is exactly [price], entirely
/// independent of `basePrice` — e.g. "Gel Al'da bu ürün her zaman 599 TL".
final class ChannelExplicitPrice extends ChannelPriceRule {
  const ChannelExplicitPrice(this.price);

  final Money price;

  @override
  bool operator ==(Object other) =>
      other is ChannelExplicitPrice && other.price == price;

  @override
  int get hashCode => price.hashCode;
}
