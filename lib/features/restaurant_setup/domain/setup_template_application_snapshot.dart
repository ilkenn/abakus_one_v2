import 'setup_template_content.dart';

/// A frozen record of what a `SetupTemplate` looked like when a tenant
/// applied it — Phase 7 (`docs/decisions.md` ADR-024). "Applied
/// templates create snapshots so later template edits do not alter
/// existing restaurants": every list here is copied at apply time, never
/// a live reference back to the mutable `SetupTemplate`.
class SetupTemplateApplicationSnapshot {
  const SetupTemplateApplicationSnapshot({
    required this.id,
    required this.templateId,
    required this.templateRevisionApplied,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.categorySuggestions,
    required this.ingredientReferences,
    required this.modifierPatterns,
    required this.appliedByStaffId,
    required this.appliedAt,
  });

  final String id;
  final String templateId;
  final int templateRevisionApplied;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final List<TemplateCategorySuggestion> categorySuggestions;
  final List<TemplateIngredientReference> ingredientReferences;
  final List<TemplateModifierPattern> modifierPatterns;
  final String appliedByStaffId;
  final DateTime appliedAt;
}
