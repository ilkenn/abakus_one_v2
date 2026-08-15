import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/providers/bowl_builder_provider.dart';

/// Provider-level coverage for the v2 live nutrition dashboard's derived
/// totals — no widget pumping needed, these are pure `Provider`s over
/// `bowlBuilderProvider`'s selection map + the catalog, exactly mirroring
/// `bowlBuilderTotalPriceProvider`'s existing shape.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  test('hicbir secim yokken tum toplamlar 0 dir', () {
    expect(container.read(bowlBuilderTotalCaloriesProvider), 0);
    expect(container.read(bowlBuilderTotalProteinProvider), 0);
    expect(container.read(bowlBuilderTotalFatProvider), 0);
    expect(container.read(bowlBuilderTotalCarbsProvider), 0);
    expect(container.read(bowlBuilderSelectedIngredientCountProvider), 0);
  });

  test('tek bir toggle malzeme dogru degerleri yansitir', () {
    // Roka: 12 kcal, 1g protein, 0g fat, 2g carb (bowl_builder_catalog.dart).
    container.read(bowlBuilderProvider.notifier).toggleIngredient(
          'bb_salad_roka',
        );

    expect(container.read(bowlBuilderTotalCaloriesProvider), 12);
    expect(container.read(bowlBuilderTotalProteinProvider), 1);
    expect(container.read(bowlBuilderTotalFatProvider), 0);
    expect(container.read(bowlBuilderTotalCarbsProvider), 2);
    expect(container.read(bowlBuilderSelectedIngredientCountProvider), 1);
  });

  test(
    'miktar-N (Proteinler/Karbonhidratlar) besin degerlerini fiyat gibi carpar',
    () {
      // Izgara Tavuk: 165 kcal, 31g protein, 4g fat, 0g carb per portion.
      container.read(bowlBuilderProvider.notifier)
        ..incrementIngredient('bb_protein_izgara_tavuk')
        ..incrementIngredient('bb_protein_izgara_tavuk')
        ..incrementIngredient('bb_protein_izgara_tavuk');

      expect(container.read(bowlBuilderTotalCaloriesProvider), 495); // 165*3
      expect(container.read(bowlBuilderTotalProteinProvider), 93); // 31*3
      expect(container.read(bowlBuilderTotalFatProvider), 12); // 4*3
      expect(container.read(bowlBuilderTotalCarbsProvider), 0);
      // A quantity-N ingredient expands into N SelectedModifier entries —
      // the count provider reuses that same expansion.
      expect(container.read(bowlBuilderSelectedIngredientCountProvider), 3);
    },
  );

  test('farkli kategorilerden birden fazla malzeme dogru toplanir', () {
    container.read(bowlBuilderProvider.notifier)
      ..incrementIngredient('bb_protein_izgara_tavuk') // 165/31/4/0
      ..toggleIngredient('bb_vegetable_domates') // 10/0/0/2
      ..toggleIngredient('bb_cheese_beyaz'); // 80/5/6/1

    expect(container.read(bowlBuilderTotalCaloriesProvider), 255); // 165+10+80
    expect(container.read(bowlBuilderTotalProteinProvider), 36); // 31+0+5
    expect(container.read(bowlBuilderTotalFatProvider), 10); // 4+0+6
    expect(container.read(bowlBuilderTotalCarbsProvider), 3); // 0+2+1
    expect(container.read(bowlBuilderSelectedIngredientCountProvider), 3);
  });

  test('bir malzeme kaldirilinca toplamlardan dogru sekilde dusulur', () {
    container.read(bowlBuilderProvider.notifier)
      ..toggleIngredient('bb_salad_roka') // 12/1/0/2
      ..toggleIngredient('bb_vegetable_domates'); // 10/0/0/2
    expect(container.read(bowlBuilderTotalCaloriesProvider), 22);

    container.read(bowlBuilderProvider.notifier).toggleIngredient(
          'bb_salad_roka',
        );

    expect(container.read(bowlBuilderTotalCaloriesProvider), 10);
    expect(container.read(bowlBuilderSelectedIngredientCountProvider), 1);
  });

  test('reset tum besin toplamlarini sifirlar', () {
    container.read(bowlBuilderProvider.notifier)
      ..incrementIngredient('bb_protein_izgara_tavuk')
      ..toggleIngredient('bb_salad_roka')
      ..reset();

    expect(container.read(bowlBuilderTotalCaloriesProvider), 0);
    expect(container.read(bowlBuilderTotalProteinProvider), 0);
    expect(container.read(bowlBuilderSelectedIngredientCountProvider), 0);
  });
}
