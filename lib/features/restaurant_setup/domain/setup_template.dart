import 'setup_template_category.dart';
import 'setup_template_content.dart';

/// A reusable, tenant-safe starting point for a restaurant type — Phase
/// 7 (`docs/decisions.md` ADR-024). "Templates are suggestions, never
/// authoritative facts" — nothing in this codebase reads a
/// `SetupTemplate` and writes a real `MenuCategory`/`MenuProduct`/
/// `Ingredient`/`Recipe` automatically; `ApplySetupTemplate` only
/// records a frozen [SetupTemplateApplicationSnapshot] of what was
/// adopted, for the admin to act on manually or through Smart Import
/// (Phase 7B).
///
/// [isPublic] `true` means a platform-owned, generic industry template
/// (`ownerOrganizationId` is `null`) — never carries confidential tenant
/// data. [isPublic] `false` means a tenant-private template
/// (`ownerOrganizationId` required) — this is how "Abaküs Street Food's
/// private recipes must not become public SaaS templates" is enforced
/// structurally: `CreateSetupTemplate` refuses a public template with an
/// owner, and a private template without one
/// (`InvalidSetupTemplateOwnershipViolation`).
///
/// Versioned via [revision] — `ApplySetupTemplate` freezes the exact
/// content into a snapshot, so a later edit to this template (a new
/// [revision]) never alters a restaurant that already applied an
/// earlier one.
class SetupTemplate {
  const SetupTemplate({
    required this.id,
    required this.category,
    required this.name,
    this.categorySuggestions = const [],
    this.ingredientReferences = const [],
    this.modifierPatterns = const [],
    this.measurementUnitHints = const [],
    this.recipePlaceholderNames = const [],
    this.stockCardSuggestionNames = const [],
    this.allergenHints = const [],
    this.nutritionDataReferenceNote,
    required this.isPublic,
    this.ownerOrganizationId,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final SetupTemplateCategory category;
  final String name;
  final List<TemplateCategorySuggestion> categorySuggestions;
  final List<TemplateIngredientReference> ingredientReferences;
  final List<TemplateModifierPattern> modifierPatterns;
  final List<String> measurementUnitHints;
  final List<String> recipePlaceholderNames;
  final List<String> stockCardSuggestionNames;
  final List<String> allergenHints;
  final String? nutritionDataReferenceNote;
  final bool isPublic;
  final String? ownerOrganizationId;
  final DateTime createdAt;
  final int revision;

  SetupTemplate copyWith({
    List<TemplateCategorySuggestion>? categorySuggestions,
    List<TemplateIngredientReference>? ingredientReferences,
    List<TemplateModifierPattern>? modifierPatterns,
    List<String>? measurementUnitHints,
    List<String>? recipePlaceholderNames,
    List<String>? stockCardSuggestionNames,
    List<String>? allergenHints,
    String? nutritionDataReferenceNote,
    required int revision,
  }) {
    return SetupTemplate(
      id: id,
      category: category,
      name: name,
      categorySuggestions: categorySuggestions ?? this.categorySuggestions,
      ingredientReferences: ingredientReferences ?? this.ingredientReferences,
      modifierPatterns: modifierPatterns ?? this.modifierPatterns,
      measurementUnitHints: measurementUnitHints ?? this.measurementUnitHints,
      recipePlaceholderNames:
          recipePlaceholderNames ?? this.recipePlaceholderNames,
      stockCardSuggestionNames:
          stockCardSuggestionNames ?? this.stockCardSuggestionNames,
      allergenHints: allergenHints ?? this.allergenHints,
      nutritionDataReferenceNote:
          nutritionDataReferenceNote ?? this.nutritionDataReferenceNote,
      isPublic: isPublic,
      ownerOrganizationId: ownerOrganizationId,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
