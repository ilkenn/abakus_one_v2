import 'package:abakus_one_v2/features/recipes/data/recipe_ingredient_link_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UnavailableRecipeIngredientLinkGateway fails closed', () async {
    const gateway = UnavailableRecipeIngredientLinkGateway();
    await expectLater(
      gateway.setLink(
        organizationId: 'org-1',
        productId: 'p1',
        recipeVersionId: 'rv-1',
        ingredients: const [],
      ),
      throwsA(isA<RecipeIngredientLinkException>()),
    );
  });
}
