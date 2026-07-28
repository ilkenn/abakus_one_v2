import 'package:abakus_one_v2/features/pos/domain/models/discount_preset_seed_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiscountPresetSeedData', () {
    test('ships exactly the 5 approved presets', () {
      expect(DiscountPresetSeedData.all, hasLength(5));
      expect(
        DiscountPresetSeedData.all.map((p) => p.percentageBasisPoints),
        [500, 1000, 1500, 2000, 2500],
      );
    });

    test('every preset id is unique', () {
      final ids = DiscountPresetSeedData.all.map((p) => p.id).toSet();
      expect(ids, hasLength(5));
    });
  });
}
