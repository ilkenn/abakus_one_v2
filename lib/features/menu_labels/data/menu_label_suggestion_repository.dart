import '../domain/menu_label_suggestion.dart';

abstract interface class MenuLabelSuggestionRepository {
  Future<void> save(MenuLabelSuggestion suggestion);
  Future<MenuLabelSuggestion?> findById(String id);
  Future<List<MenuLabelSuggestion>> findByRecipeVersionId(
      String recipeVersionId);
}

class InMemoryMenuLabelSuggestionRepository
    implements MenuLabelSuggestionRepository {
  final Map<String, MenuLabelSuggestion> _byId = {};

  @override
  Future<void> save(MenuLabelSuggestion suggestion) async =>
      _byId[suggestion.id] = suggestion;

  @override
  Future<MenuLabelSuggestion?> findById(String id) async => _byId[id];

  @override
  Future<List<MenuLabelSuggestion>> findByRecipeVersionId(
      String recipeVersionId) async {
    return List.unmodifiable(
      _byId.values.where((s) => s.recipeVersionId == recipeVersionId),
    );
  }
}
