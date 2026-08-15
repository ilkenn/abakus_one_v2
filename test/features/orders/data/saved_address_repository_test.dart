import 'package:abakus_one_v2/features/orders/data/saved_address_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slugifyAddressComponent', () {
    test('lowercases and folds Turkish characters', () {
      expect(slugifyAddressComponent('Beşiktaş'), 'besiktas');
      expect(slugifyAddressComponent('Şişli'), 'sisli');
      expect(slugifyAddressComponent('Kağıthane'), 'kagithane');
      expect(slugifyAddressComponent('İstanbul'), 'istanbul');
    });

    test('replaces whitespace with underscores', () {
      expect(slugifyAddressComponent('H. Rıfat Paşa'), 'h_rifat_pasa');
    });

    test('is stable for the same input', () {
      expect(slugifyAddressComponent('Balmumcu'),
          slugifyAddressComponent('Balmumcu'));
    });
  });
}
