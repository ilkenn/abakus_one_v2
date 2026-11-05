import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../domain/models/cart_item.dart';
import 'dine_in_table_cart_notifier.dart';

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    return const [];
  }

  /// The exact key `addToCart` uses to decide "same configuration, bump
  /// quantity" vs "new line" — pulled out so a subclass (Self-Order QR
  /// Faz 3's `DineInTableCartNotifier`) can compute the identical key for
  /// its own, Firestore-backed merge logic without duplicating this rule.
  String computeCustomizationsKey({
    required String id,
    required String selectedProtein,
    required String selectedSauce,
    required List<String> removedIngredients,
    required List<String> extraIngredients,
    required List<SelectedModifier> selectedModifiers,
    required String note,
    required String customizationsKey,
  }) {
    if (customizationsKey.isNotEmpty) return customizationsKey;
    final sortedModifierIds = selectedModifiers.map((m) => m.optionId).toList()
      ..sort();
    return '${id}_${selectedProtein}_${selectedSauce}_${removedIngredients.join(",")}_${extraIngredients.join(",")}_${sortedModifierIds.join(",")}_$note';
  }

  void addToCart({
    required String id,
    required String name,
    required String desc,
    required double price,
    int quantity = 1,
    String selectedProtein = '',
    String selectedSauce = '',
    List<String> removedIngredients = const [],
    List<String> extraIngredients = const [],
    double extraCostPerUnit = 0.0,
    List<SelectedModifier> selectedModifiers = const [],
    String note = '',
    String customizationsKey = '',
    OrderChannel? pricedForChannel,
  }) {
    final String targetKey = computeCustomizationsKey(
      id: id,
      selectedProtein: selectedProtein,
      selectedSauce: selectedSauce,
      removedIngredients: removedIngredients,
      extraIngredients: extraIngredients,
      selectedModifiers: selectedModifiers,
      note: note,
      customizationsKey: customizationsKey,
    );

    final existingIndex = state.indexWhere((item) =>
        (item.customizationsKey.isNotEmpty &&
            item.customizationsKey == targetKey) ||
        (item.customizationsKey.isEmpty &&
            item.id == id &&
            item.selectedProtein == selectedProtein &&
            item.selectedSauce == selectedSauce));

    if (existingIndex >= 0) {
      final existingItem = state[existingIndex];
      state = [
        ...state.sublist(0, existingIndex),
        existingItem.copyWith(quantity: existingItem.quantity + quantity),
        ...state.sublist(existingIndex + 1),
      ];
    } else {
      state = [
        ...state,
        CartItem(
          id: id,
          name: name,
          desc: desc,
          price: price,
          quantity: quantity,
          selectedProtein: selectedProtein,
          selectedSauce: selectedSauce,
          removedIngredients: removedIngredients,
          extraIngredients: extraIngredients,
          extraCostPerUnit: extraCostPerUnit,
          selectedModifiers: selectedModifiers,
          note: note,
          customizationsKey: targetKey,
          pricedForChannel: pricedForChannel,
        ),
      ];
    }
  }

  void incrementQuantity(String targetKey) {
    state = [
      for (final item in state)
        if (item.customizationsKey == targetKey)
          item.copyWith(quantity: item.quantity + 1)
        else
          item
    ];
  }

  void decrementQuantity(String targetKey) {
    final hasMatch =
        state.any((element) => element.customizationsKey == targetKey);
    if (!hasMatch) {
      return;
    }
    final item =
        state.firstWhere((element) => element.customizationsKey == targetKey);
    if (item.quantity <= 1) {
      removeFromCart(customizationsKey: targetKey);
      return;
    }
    state = [
      for (final item in state)
        if (item.customizationsKey == targetKey)
          item.copyWith(quantity: item.quantity - 1)
        else
          item
    ];
  }

  void updateQuantity(
      String id, String protein, String sauce, int newQuantity) {
    final index = state.indexWhere((item) =>
        item.id == id &&
        item.selectedProtein == protein &&
        item.selectedSauce == sauce);
    if (index >= 0) {
      if (newQuantity <= 0) {
        removeFromCart(id: id, selectedProtein: protein, selectedSauce: sauce);
        return;
      }
      final targetKey = state[index].customizationsKey;
      state = [
        for (final item in state)
          if (item.customizationsKey == targetKey)
            item.copyWith(quantity: newQuantity)
          else
            item
      ];
    }
  }

  void removeFromCart({
    String? id,
    String? selectedProtein,
    String? selectedSauce,
    String? customizationsKey,
  }) {
    if (customizationsKey != null && customizationsKey.isNotEmpty) {
      state = state
          .where((item) => item.customizationsKey != customizationsKey)
          .toList();
    } else if (id != null) {
      state = state
          .where((item) => !(item.id == id &&
              item.selectedProtein == (selectedProtein ?? '') &&
              item.selectedSauce == (selectedSauce ?? '')))
          .toList();
    }
  }

  void clearCart() {
    state = const [];
  }

  /// Replaces the entire cart contents at once — Faz R.2, used by
  /// `_PreorderCartBridge` to mirror a scoped `CartNotifier` instance's
  /// state into `preorderCartProvider`'s own instance of this same class.
  /// `Notifier.state` itself isn't settable from outside a `Notifier`
  /// subclass in this Riverpod version, hence this explicit method.
  void replaceAll(List<CartItem> items) {
    state = items;
  }
}

/// Self-Order QR Faz 3 — the real, app-wide cart is a
/// [DineInTableCartNotifier] (a [CartNotifier] subclass) so it can
/// transparently mirror the live, shared `tableSessionCarts` collection
/// whenever a table context is active, while behaving identically to the
/// plain base class for every other channel. `preorderCartProvider`
/// (`features/reservation`) deliberately keeps instantiating the plain
/// `CartNotifier` directly — never this subclass — so its own isolated
/// cart never reacts to `activeTableContextProvider` at all.
final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(() {
  return DineInTableCartNotifier();
});

final cartTotalPriceProvider = Provider<double>((ref) {
  final cartItems = ref.watch(cartProvider);
  return cartItems.fold(0.0, (sum, item) => sum + item.totalRowPrice);
});

final cartTotalItemsCountProvider = Provider<int>((ref) {
  final cartItems = ref.watch(cartProvider);
  return cartItems.fold(0, (sum, item) => sum + item.quantity);
});

final cartTotalItemsProvider = Provider<int>((ref) {
  return ref.watch(cartTotalItemsCountProvider);
});
