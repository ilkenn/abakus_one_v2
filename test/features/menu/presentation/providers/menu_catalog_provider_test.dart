import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';

const _withAllergens = MenuProduct(
  id: 'prod_allergens',
  categoryId: 'test_cat',
  name: 'Allerjenli Ürün',
  description: 'Test açıklaması',
  basePrice: 50,
  imageKey: 'does-not-exist',
  allergens: ['gluten', 'süt'],
);

const _withoutAllergens = MenuProduct(
  id: 'prod_plain',
  categoryId: 'test_cat',
  name: 'Sade Ürün',
  description: 'Test açıklaması',
  basePrice: 30,
  imageKey: 'does-not-exist',
);

const _availableDrink = MenuProduct(
  id: 'drink_available',
  categoryId: 'cat_icecekler',
  name: 'Müsait İçecek',
  description: 'Test açıklaması',
  basePrice: 20,
  imageKey: 'does-not-exist',
);

const _soldOutDrink = MenuProduct(
  id: 'drink_sold_out',
  categoryId: 'cat_icecekler',
  name: 'Tükenen İçecek',
  description: 'Test açıklaması',
  basePrice: 20,
  imageKey: 'does-not-exist',
  isAvailable: false,
);

void main() {
  test(
    'availableAllergensProvider aktif urunlerdeki tum alerjenleri '
    'tekrarsiz ve siralanmis dondurur',
    () {
      final container = ProviderContainer(
        overrides: [
          menuProductsProvider.overrideWithValue(
            [_withAllergens, _withoutAllergens],
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(availableAllergensProvider),
        ['gluten', 'süt'],
      );
    },
  );

  test(
    'hicbir urunde alerjen yoksa availableAllergensProvider bos liste '
    'dondurur',
    () {
      final container = ProviderContainer(
        overrides: [
          menuProductsProvider.overrideWithValue([_withoutAllergens]),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(availableAllergensProvider), isEmpty);
    },
  );

  test(
    'drinkCrossSellProductsProvider tukenen (isAvailable == false) '
    'icecekleri listeye almaz',
    () {
      final container = ProviderContainer(
        overrides: [
          menuProductsProvider.overrideWithValue(
            [_availableDrink, _soldOutDrink],
          ),
        ],
      );
      addTearDown(container.dispose);

      final drinks = container.read(drinkCrossSellProductsProvider);

      expect(drinks, [_availableDrink]);
    },
  );
}
