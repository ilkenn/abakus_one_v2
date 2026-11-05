import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/allergen_filter_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('baslangicta hicbir alerjen disarida tutulmaz', () {
    expect(container.read(allergenFilterProvider), isEmpty);
  });

  test('toggle bir alerjeni disari cikarma kumesine ekler', () {
    container.read(allergenFilterProvider.notifier).toggle('gluten');

    expect(container.read(allergenFilterProvider), {'gluten'});
  });

  test('ayni alerjeni ikinci kez toggle etmek kumeden cikarir', () {
    final notifier = container.read(allergenFilterProvider.notifier);
    notifier.toggle('gluten');
    notifier.toggle('gluten');

    expect(container.read(allergenFilterProvider), isEmpty);
  });

  test('birden fazla alerjen bagimsiz olarak izlenebilir', () {
    final notifier = container.read(allergenFilterProvider.notifier);
    notifier.toggle('gluten');
    notifier.toggle('süt');

    expect(container.read(allergenFilterProvider), {'gluten', 'süt'});

    notifier.toggle('gluten');

    expect(container.read(allergenFilterProvider), {'süt'});
  });

  test('clear() tum secimleri sifirlar', () {
    final notifier = container.read(allergenFilterProvider.notifier);
    notifier.toggle('gluten');
    notifier.toggle('süt');

    notifier.clear();

    expect(container.read(allergenFilterProvider), isEmpty);
  });
}
