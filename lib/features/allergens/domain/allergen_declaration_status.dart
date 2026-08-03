/// One ingredient's declared relationship to one [AllergenType] —
/// Phase 7 (`docs/decisions.md` ADR-024). [unknown] is a real,
/// distinct state — "unknown never presented as allergen-free"; only
/// [explicitlyFreeFrom] may ever be shown to a customer as a
/// free-from guarantee.
enum AllergenDeclarationStatus {
  contains,
  mayContain,
  crossContaminationRisk,
  explicitlyFreeFrom,
  unknown,
}
