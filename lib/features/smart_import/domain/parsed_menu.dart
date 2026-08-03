import 'import_issue.dart';
import 'parsed_category.dart';
import 'parsed_ingredient_suggestion.dart';
import 'parsed_product.dart';
import 'parsed_recipe_suggestion.dart';

/// The full, structured result of parsing+normalizing+analyzing one
/// [ImportSource] — Phase 7 (`docs/decisions.md` ADR-024). Pure data,
/// produced by `ParseImportSource`/`NormalizeParsedMenu`/
/// `AnalyzeParsedMenu` — never itself written to any domain repository;
/// see `ImportDraft` for the persisted, reviewable wrapper around one.
class ParsedMenu {
  const ParsedMenu({
    this.categories = const [],
    this.products = const [],
    this.ingredientSuggestions = const [],
    this.recipeSuggestions = const [],
    this.issues = const [],
  });

  final List<ParsedCategory> categories;
  final List<ParsedProduct> products;
  final List<ParsedIngredientSuggestion> ingredientSuggestions;
  final List<ParsedRecipeSuggestion> recipeSuggestions;
  final List<ImportIssue> issues;

  ParsedMenu copyWith({
    List<ParsedCategory>? categories,
    List<ParsedProduct>? products,
    List<ParsedIngredientSuggestion>? ingredientSuggestions,
    List<ParsedRecipeSuggestion>? recipeSuggestions,
    List<ImportIssue>? issues,
  }) {
    return ParsedMenu(
      categories: categories ?? this.categories,
      products: products ?? this.products,
      ingredientSuggestions:
          ingredientSuggestions ?? this.ingredientSuggestions,
      recipeSuggestions: recipeSuggestions ?? this.recipeSuggestions,
      issues: issues ?? this.issues,
    );
  }
}
