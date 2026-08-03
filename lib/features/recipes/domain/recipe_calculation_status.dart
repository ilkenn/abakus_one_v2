/// The trust state of a derived recipe-adjacent calculation (nutrition,
/// allergens, cost) — Phase 7 (`docs/decisions.md` ADR-024). Shared
/// across 7H/7I/7J/7K/7M rather than duplicating three near-identical
/// status enums — "never fabricate a value; missing data produces an
/// honest incomplete status, not zero."
enum RecipeCalculationStatus {
  /// No calculation engine has run against this record yet (e.g. a
  /// Bowl Builder snapshot created before 7J/7K/7M wire in).
  notYetCalculated,

  /// The engine ran and every input it needed was available.
  calculated,

  /// The engine ran but at least one required input (an ingredient's
  /// nutrition reference, an allergen classification, a purchase
  /// price) was missing — the result is a partial, honestly-labeled
  /// estimate, never silently treated as complete or zero.
  incomplete,
}
