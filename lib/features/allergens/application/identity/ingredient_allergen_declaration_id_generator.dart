abstract interface class IngredientAllergenDeclarationIdGenerator {
  String nextIngredientAllergenDeclarationId();
}

class SequentialIngredientAllergenDeclarationIdGenerator
    implements IngredientAllergenDeclarationIdGenerator {
  SequentialIngredientAllergenDeclarationIdGenerator({
    this.prefix = 'allergen-declaration',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextIngredientAllergenDeclarationId() => '$prefix-${++_sequence}';
}
