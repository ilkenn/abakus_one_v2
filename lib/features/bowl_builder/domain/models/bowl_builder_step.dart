/// The ordered steps of the "Kendi Bowlunu / Salatanı Yarat" flow.
///
/// Each step but `summary` corresponds to one of Bowl Builder's 9 ingredient
/// categories (see `BowlBuilderCategory`) — this enum value's `.name` is
/// exactly that category's `id`, so the screen resolves a step's category
/// via `catalog.categories` without a separate step-to-category map.
/// `summary` is the final review step; "Sepete Ekle" is the action taken
/// from `summary`, not a step of its own.
///
/// No category is required, and there is no starting price on top of
/// selected ingredients (product decision, 2026-07-23) — a customer may add
/// the bowl to the cart with zero selections, which prices it at 0 TL.
enum BowlBuilderStep {
  protein,
  carbs,
  salads,
  vegetables,
  fruits,
  pickles,
  cheeses,
  others,
  sauces,
  summary,
}

extension BowlBuilderStepX on BowlBuilderStep {
  /// The next step, or `null` if this is the last one.
  BowlBuilderStep? get next {
    const values = BowlBuilderStep.values;
    final index = values.indexOf(this);
    if (index >= values.length - 1) return null;
    return values[index + 1];
  }

  /// The previous step, or `null` if this is the first one.
  BowlBuilderStep? get previous {
    const values = BowlBuilderStep.values;
    final index = values.indexOf(this);
    if (index <= 0) return null;
    return values[index - 1];
  }
}
