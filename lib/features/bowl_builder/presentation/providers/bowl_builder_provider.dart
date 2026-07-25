import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../data/bowl_builder_catalog.dart';
import '../../domain/models/bowl_builder_state.dart';
import '../../domain/models/bowl_builder_step.dart';

/// The [BowlBuilderCatalogRepository] implementation currently in use.
/// Mirrors `ordersRepositoryProvider`/`authRepositoryProvider`: a future
/// admin-configured/remote-backed catalog overrides only this provider —
/// nothing in [BowlBuilderNotifier], the pricing providers below, or any
/// screen depends on [LocalBowlBuilderCatalogRepository] directly.
final bowlBuilderCatalogRepositoryProvider =
    Provider<BowlBuilderCatalogRepository>((ref) {
  return const LocalBowlBuilderCatalogRepository();
});

class BowlBuilderNotifier extends Notifier<BowlBuilderState> {
  @override
  BowlBuilderState build() => const BowlBuilderState();

  void _setQuantity(String ingredientId, int quantity) {
    final updated = Map<String, int>.from(
      state.selectedQuantitiesByIngredient,
    );
    if (quantity <= 0) {
      updated.remove(ingredientId);
    } else {
      updated[ingredientId] = quantity;
    }
    state = state.copyWith(selectedQuantitiesByIngredient: updated);
  }

  /// Toggle-style selection for the 7 non-quantity categories: `0` ↔ `1`.
  /// Tapping an already-selected ingredient removes it; there is no cap on
  /// how many distinct ingredients can be toggled on.
  void toggleIngredient(String ingredientId) {
    _setQuantity(ingredientId, state.quantityFor(ingredientId) > 0 ? 0 : 1);
  }

  /// +1 for a quantity-category ingredient (Proteinler/Karbonhidratlar) —
  /// no upper bound, the same ingredient can be added as many times as
  /// wanted.
  void incrementIngredient(String ingredientId) {
    _setQuantity(ingredientId, state.quantityFor(ingredientId) + 1);
  }

  /// -1 for a quantity-category ingredient; never goes below 0.
  void decrementIngredient(String ingredientId) {
    final next = state.quantityFor(ingredientId) - 1;
    _setQuantity(ingredientId, next < 0 ? 0 : next);
  }

  void incrementQuantity() {
    state = state.copyWith(quantity: state.quantity + 1);
  }

  void decrementQuantity() {
    if (state.quantity <= 1) return;
    state = state.copyWith(quantity: state.quantity - 1);
  }

  void setNote(String note) {
    state = state.copyWith(note: note);
  }

  void goToStep(BowlBuilderStep step) {
    state = state.copyWith(currentStep: step);
  }

  void nextStep() {
    final next = state.currentStep.next;
    if (next != null) state = state.copyWith(currentStep: next);
  }

  void previousStep() {
    final previous = state.currentStep.previous;
    if (previous != null) state = state.copyWith(currentStep: previous);
  }

  void reset() {
    state = const BowlBuilderState();
  }
}

final bowlBuilderProvider =
    NotifierProvider<BowlBuilderNotifier, BowlBuilderState>(() {
  return BowlBuilderNotifier();
});

/// Every selected ingredient, across all categories, as cart-ready
/// [SelectedModifier]s. A quantity-N ingredient (Proteinler/Karbonhidratlar)
/// produces N separate entries with the same id/name/price rather than one
/// entry carrying a `quantity` field — `SelectedModifier`/`CartItem` are
/// untouched by this feature's pricing model change, and summing N
/// duplicate entries already prices an ingredient added 3 times as
/// `price × 3` with zero changes to the shared cart model.
final bowlBuilderSelectedModifiersProvider =
    Provider<List<SelectedModifier>>((ref) {
  final state = ref.watch(bowlBuilderProvider);
  final catalog = ref.watch(bowlBuilderCatalogRepositoryProvider);
  final result = <SelectedModifier>[];

  state.selectedQuantitiesByIngredient.forEach((ingredientId, quantity) {
    final ingredient = catalog.ingredientById(ingredientId);
    if (ingredient == null) return;
    String categoryName = ingredient.categoryId;
    for (final category in catalog.categories) {
      if (category.id == ingredient.categoryId) {
        categoryName = category.name;
        break;
      }
    }

    for (var i = 0; i < quantity; i++) {
      result.add(SelectedModifier(
        groupId: ingredient.categoryId,
        groupName: categoryName,
        optionId: ingredient.id,
        optionName: ingredient.name,
        extraPrice: ingredient.price,
      ));
    }
  });

  return result;
});

/// Unit price for one bowl: purely the sum of every selected ingredient's
/// price (product decision, 2026-07-23 — no starting price, no included/
/// free tier). This is what gets passed to the cart as the line's
/// `selectedModifiers`; `CartItem.unitPrice`/`totalRowPrice` handle
/// multiplying by the bowl's own order quantity, so this provider must
/// never also do that (would double-count once the item reaches the cart).
final bowlBuilderTotalPriceProvider = Provider<double>((ref) {
  final selectedModifiers = ref.watch(bowlBuilderSelectedModifiersProvider);
  return selectedModifiers.fold(0.0, (sum, m) => sum + m.extraPrice);
});

/// Display-only preview of the full amount for the chosen bowl order
/// quantity, shown before the bowl is added to the cart. Purely `unitPrice *
/// quantity` — once in the cart, `CartItem.totalRowPrice` is the single
/// source of truth for this same multiplication.
final bowlBuilderGrandTotalProvider = Provider<double>((ref) {
  final unitPrice = ref.watch(bowlBuilderTotalPriceProvider);
  final quantity = ref.watch(bowlBuilderProvider).quantity;
  return unitPrice * quantity;
});
