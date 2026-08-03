/// Where an [IngredientAllergenDeclaration] came from — Phase 7
/// (`docs/decisions.md` ADR-024). [aiSuggested] entries are never
/// authoritative on their own — see
/// `IngredientAllergenDeclaration.isConfirmedByHuman`.
enum AllergenSourceType { manual, aiSuggested, externalProvider }
