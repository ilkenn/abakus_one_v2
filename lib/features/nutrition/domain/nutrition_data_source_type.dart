/// Where a [NutritionReferenceEntry]'s values came from — Phase 7
/// (`docs/decisions.md` ADR-024). [externalProvider] is a contract
/// only this phase — "provider contracts for trusted food databases,"
/// no paid AI/OCR service and no real vendor wired in (out of scope).
enum NutritionDataSourceType { manual, externalProvider }
