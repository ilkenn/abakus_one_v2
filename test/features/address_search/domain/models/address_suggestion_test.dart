import 'package:abakus_one_v2/features/address_search/domain/models/address_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('two suggestions with the same values are equal', () {
    const a = AddressSuggestion(providerPlaceId: 'place-1', text: 'Beşiktaş');
    const b = AddressSuggestion(providerPlaceId: 'place-1', text: 'Beşiktaş');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('a different providerPlaceId breaks equality', () {
    const a = AddressSuggestion(providerPlaceId: 'place-1', text: 'Beşiktaş');
    const b = AddressSuggestion(providerPlaceId: 'place-2', text: 'Beşiktaş');
    expect(a, isNot(b));
  });
}
