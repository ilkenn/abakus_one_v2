/// How trustworthy one [IngredientAllergenDeclaration] is judged to
/// be — Phase 7 (`docs/decisions.md` ADR-024). Kept as its own type,
/// not `NutritionConfidence` — each bounded context owns its own
/// vocabulary (continues the "separate audit type per bounded
/// context" precedent one level further).
enum AllergenConfidence { unknown, low, medium, high }
