import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cart/domain/models/cart_item.dart';
import '../../../cart/presentation/providers/cart_provider.dart';

/// A second, fully independent cart — Faz R.2 §11/D4. `CartNotifier`
/// itself is already product-agnostic (the same class the real shopping
/// cart uses); this is a genuinely separate global provider instance, not
/// the app's own [cartProvider] reused or parameterized — mirrors this
/// codebase's own established precedent of a separate, self-contained
/// implementation over a parameterized shared one (e.g.
/// `TakeawayCheckoutScreen` vs `DineInCheckoutScreen`).
///
/// **Isolation mechanism**: `ReservationPreorderScope` wraps the preorder
/// sub-flow's nested `Navigator` in its own `ProviderScope` with a fresh,
/// independent [cartProvider] override — so unmodified
/// `ProductDetailScreen`/`BowlBuilderScreen`, which both hardcode
/// `ref.read(cartProvider.notifier)`, write into that isolated instance
/// instead of the app's real one, purely because of *where in the widget
/// tree* they were pushed from. A bridge widget inside that scope mirrors
/// every change from the isolated instance into this provider, which is
/// what the rest of the reservation flow (review step, submit payload)
/// actually reads. The real global `cartProvider`, read from anywhere
/// outside that subtree, is never touched — proven by
/// `reservation_preorder_scope_test.dart`.
final preorderCartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

final preorderCartTotalPriceProvider = Provider<double>((ref) {
  final items = ref.watch(preorderCartProvider);
  return items.fold(0.0, (sum, item) => sum + item.totalRowPrice);
});

final preorderCartTotalItemsCountProvider = Provider<int>((ref) {
  final items = ref.watch(preorderCartProvider);
  return items.fold(0, (sum, item) => sum + item.quantity);
});
