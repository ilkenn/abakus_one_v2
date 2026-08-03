/// A rule-driven menu label suggestion category — Phase 7
/// (`docs/decisions.md` ADR-024). [vegan]/[vegetarian]/[spicy]/
/// [athleteFriendly] have no automatic evaluator this phase (no
/// ingredient-level vegan/vegetarian/spice classification exists yet
/// in `features/inventory` — inventing one would be an uncoordinated
/// domain-model change outside this part's scope); `MenuLabelRuleEvaluator`
/// honestly reports them as not automatically evaluable rather than
/// guessing. [highProtein]/[lowCalorie]/[highFiber] evaluate against
/// `NutritionCalculationResult`; [glutenFree]/[lactoseFree] evaluate
/// against confirmed `IngredientAllergenDeclaration`s.
enum MenuLabelType {
  highProtein,
  vegan,
  vegetarian,
  glutenFree,
  lactoseFree,
  lowCalorie,
  spicy,
  athleteFriendly,
  highFiber,
}
