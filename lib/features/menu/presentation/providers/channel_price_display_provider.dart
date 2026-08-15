import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../cart/domain/models/shopping_channel_context.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../domain/models/menu_product.dart';
import '../../domain/pricing/channel_price_resolver.dart';
import '../../domain/pricing/channel_pricing_policy.dart';
import 'channel_pricing_provider.dart';

/// A live snapshot of the current [ChannelPricingPolicy] — Faz C is the
/// first presentation-layer consumer of `ChannelPriceResolver`/
/// `ChannelPricingPolicyRepository` (Faz A built the engine, deliberately
/// unwired from any screen until a real channel-selection flow existed).
///
/// `.valueOrNull ?? const ChannelPricingPolicy()` at every call site
/// (never this provider's own concern) means "no adjustment yet" while
/// the repository read is in flight — a fast, in-memory read in practice,
/// so this is a brief, harmless flash of the base price, never a stuck
/// loading state.
final channelPricingPolicySnapshotProvider =
    FutureProvider<ChannelPricingPolicy>((ref) {
  return ref.watch(channelPricingPolicyRepositoryProvider).current();
});

/// Resolves the price a customer should actually see for [product] under
/// [channelContext] — [product.basePrice] unchanged for every channel this
/// app doesn't yet configure a policy for (dine-in, delivery — Faz A's own
/// "channel not configured = zero adjustment" guarantee), or the resolved
/// Gel Al price when [channelContext] is takeaway. Returns the same
/// `double` shape every existing screen already works with (the
/// `Money`/channel-pricing machinery stays an internal implementation
/// detail of this one boundary).
double resolveDisplayPrice({
  required MenuProduct product,
  required ShoppingChannelContext channelContext,
  required ChannelPricingPolicy policy,
}) {
  if (!channelContext.isTakeaway) return product.basePrice;
  final resolved = ChannelPriceResolver.resolveProductUnitPrice(
    product: product,
    categoryId: product.categoryId,
    channel: OrderChannel.takeaway,
    policy: policy,
  );
  return resolved.minorUnits / resolved.currency.minorUnitsPerWhole;
}
