/// A suggested menu category name — never authoritative, see
/// `SetupTemplate`'s own doc comment.
class TemplateCategorySuggestion {
  const TemplateCategorySuggestion({required this.tempId, required this.name});
  final String tempId;
  final String name;
}

/// A named reference into a common ingredient vocabulary — not a real
/// `Ingredient` (Phase 7F), just a suggested name a tenant may later
/// create one from.
class TemplateIngredientReference {
  const TemplateIngredientReference({required this.tempId, required this.name});
  final String tempId;
  final String name;
}

/// A commonly-seen modifier group shape (e.g. "Boyut" with options
/// "Küçük"/"Orta"/"Büyük") — suggested structure, not a real
/// `ModifierGroup`.
class TemplateModifierPattern {
  const TemplateModifierPattern({
    required this.tempId,
    required this.name,
    this.optionNames = const [],
  });
  final String tempId;
  final String name;
  final List<String> optionNames;
}
