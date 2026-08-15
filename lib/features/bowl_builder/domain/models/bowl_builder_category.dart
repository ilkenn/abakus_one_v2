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
///
/// [displayName] (added for the v2 category-driven redesign, 2026-08-08) is
/// a customer-facing label override for when the catalog's own [name]
/// shouldn't be shown verbatim — today only "Diğerleri" uses this, displayed
/// as "Ekstralar" — while [id] (`'others'`) and [name] (`'Diğerleri'`) stay
/// unchanged everywhere else in the system. `null` (every other category)
/// means "show [name] as-is". UI code should always read
/// `category.displayName ?? category.name`, never [name] directly, so this
/// stays the single place the override lives.
class BowlBuilderCategory {
  final String id;
  final String name;
  final bool allowsQuantity;
  final String? displayName;

  const BowlBuilderCategory({
    required this.id,
    required this.name,
    this.allowsQuantity = false,
    this.displayName,
  });
}
