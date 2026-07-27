/// A candidate modifier selection to validate against a `ModifierGroup`
/// — an option id plus how many units of it were picked. Not priced or
/// frozen; that happens only after `ModifierValidator` accepts it (see
/// `OrderLineModifierSelection`, the frozen counterpart built once
/// validation passes).
class ModifierSelectionInput {
  const ModifierSelectionInput(
      {required this.optionId, required this.quantity});

  final String optionId;
  final int quantity;
}
