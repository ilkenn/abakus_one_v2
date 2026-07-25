import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../domain/models/cart_item.dart';

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    return const [];
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
  }) {
    final sortedModifierIds = selectedModifiers.map((m) => m.optionId).toList()
      ..sort();

    final String targetKey = customizationsKey.isNotEmpty
        ? customizationsKey
        : '${id}_${selectedProtein}_${selectedSauce}_${removedIngredients.join(",")}_${extraIngredients.join(",")}_${sortedModifierIds.join(",")}_$note';

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
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(() {
  return CartNotifier();
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
