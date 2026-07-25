import 'bowl_builder_step.dart';

/// Current progress through the Bowl Builder flow.
///
/// [selectedQuantitiesByIngredient] maps an ingredient id to how many of it
/// are selected — `0` (or absent) means not selected. This single shape
/// covers both interaction modes: toggle categories only ever store `0` or
/// `1` per ingredient; Proteinler/Karbonhidratlar can store any count via
/// their +/- stepper. There is no per-category cap and nothing is required.
class BowlBuilderState {
  final BowlBuilderStep currentStep;
  final Map<String, int> selectedQuantitiesByIngredient;

  /// How many of this exact bowl configuration to add to the cart — the
  /// bowl's own order quantity, unrelated to any single ingredient's count.
  final int quantity;
  final String note;

  const BowlBuilderState({
    this.currentStep = BowlBuilderStep.protein,
    this.selectedQuantitiesByIngredient = const {},
    this.quantity = 1,
    this.note = '',
  });

  int quantityFor(String ingredientId) =>
      selectedQuantitiesByIngredient[ingredientId] ?? 0;

  BowlBuilderState copyWith({
    BowlBuilderStep? currentStep,
    Map<String, int>? selectedQuantitiesByIngredient,
    int? quantity,
    String? note,
  }) {
    return BowlBuilderState(
      currentStep: currentStep ?? this.currentStep,
      selectedQuantitiesByIngredient:
          selectedQuantitiesByIngredient ?? this.selectedQuantitiesByIngredient,
      quantity: quantity ?? this.quantity,
      note: note ?? this.note,
    );
  }
}
