import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../qr/presentation/providers/active_table_context_provider.dart';
import '../../domain/models/shopping_channel_context.dart';

class ShoppingChannelNotifier extends Notifier<ShoppingChannelContext> {
  /// 2026-11-11 — while a QR table session is active the channel IS
  /// [OrderChannel.dineInQr], derived here (every QR entry path sets
  /// `activeTableContextProvider`, none had to remember to switch the
  /// channel). Previously the channel stayed `delivery` at the table, so
  /// every shared-cart line (always `dineInQr`) looked "priced for a
  /// different channel", the cart showed the stale-items warning and the
  /// checkout button stayed locked; menu prices/modifier visibility were
  /// resolved for delivery too. Leaving the table rebuilds back to
  /// delivery.
  @override
  ShoppingChannelContext build() {
    final table = ref.watch(activeTableContextProvider);
    if (table != null) {
      return ShoppingChannelContext(
        channel: OrderChannel.dineInQr,
        restaurantId: table.restaurantId,
        branchId: table.branchId,
        branchDisplayName: table.branchName,
      );
    }
    return const ShoppingChannelContext.delivery();
  }

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
