import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../domain/models/shopping_channel_context.dart';

class ShoppingChannelNotifier extends Notifier<ShoppingChannelContext> {
  @override
  ShoppingChannelContext build() => const ShoppingChannelContext.delivery();

  void selectTakeaway({
    required String restaurantId,
    required String branchId,
    required String branchDisplayName,
  }) {
    state = ShoppingChannelContext(
      channel: OrderChannel.takeaway,
      restaurantId: restaurantId,
      branchId: branchId,
      branchDisplayName: branchDisplayName,
    );
  }

  void reset() {
    state = const ShoppingChannelContext.delivery();
  }
}

final shoppingChannelProvider =
    NotifierProvider<ShoppingChannelNotifier, ShoppingChannelContext>(() {
  return ShoppingChannelNotifier();
});
