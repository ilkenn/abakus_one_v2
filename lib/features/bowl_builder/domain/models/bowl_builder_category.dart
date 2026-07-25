/// One of Bowl Builder's 9 ingredient categories.
///
/// [id] intentionally matches the corresponding `BowlBuilderStep` enum
/// value's `.name` — the screen maps a step to its category via that shared
/// name instead of a separate lookup table.
///
/// [allowsQuantity] is true only for Proteinler/Karbonhidratlar (product
/// decision, 2026-07-23): those two support a per-ingredient +/- stepper —
/// the same ingredient can be added multiple times, `price × quantity`.
/// Every other category is a simple toggle: one portion per ingredient, tap
/// again to remove it, no cap on how many distinct ingredients can be
/// selected.
class BowlBuilderCategory {
  final String id;
  final String name;
  final bool allowsQuantity;

  const BowlBuilderCategory({
    required this.id,
    required this.name,
    this.allowsQuantity = false,
  });
}
