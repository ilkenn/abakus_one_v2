/// How trustworthy one [NutritionReferenceEntry]'s values are judged
/// to be — Phase 7 (`docs/decisions.md` ADR-024). Set by whoever
/// records the entry ([NutritionDataSourceType.manual] entries default
/// to [low] until reviewed; see `ReviewNutritionReferenceEntry`) —
/// never inferred or fabricated by this codebase.
enum NutritionConfidence { unknown, low, medium, high }
