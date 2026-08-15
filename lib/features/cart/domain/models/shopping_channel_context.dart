import '../../../orders/domain/models/order_channel.dart';

/// The customer app's "which channel/branch am I currently shopping
/// under" state — Faz C (Gel Al authenticated in-app ordering). Mirrors
/// `features/qr`'s `ActiveTableContext` role for the dine-in-QR flow: a
/// client-side-only aggregate bundling what the shopping chain (Menu →
/// Product Detail → Bowl Builder → Cart → Checkout) needs to answer "what
/// channel is this, and which branch," so a product-price lookup doesn't
/// have to separately reconstruct that context on every screen.
///
/// [OrderChannel.delivery] with a `null` [branchId] is this app's existing,
/// unchanged default (today's only real customer-app flow before Faz C) —
/// selecting Gel Al is the one thing that ever changes this away from that
/// default; dine-in-QR continues to run entirely through the separate
/// `ActiveTableContext`/`DineInCheckoutScreen` path, untouched.
class ShoppingChannelContext {
  final OrderChannel channel;
  final String? restaurantId;
  final String? branchId;
  final String? branchDisplayName;

  const ShoppingChannelContext({
    required this.channel,
    this.restaurantId,
    this.branchId,
    this.branchDisplayName,
  });

  const ShoppingChannelContext.delivery()
      : channel = OrderChannel.delivery,
        restaurantId = null,
        branchId = null,
        branchDisplayName = null;

  bool get isTakeaway => channel == OrderChannel.takeaway;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ShoppingChannelContext &&
            other.channel == channel &&
            other.restaurantId == restaurantId &&
            other.branchId == branchId &&
            other.branchDisplayName == branchDisplayName);
  }

  @override
  int get hashCode =>
      Object.hash(channel, restaurantId, branchId, branchDisplayName);
}
