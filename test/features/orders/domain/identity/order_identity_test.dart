import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryOrderIdentityProvider', () {
    test('nextOrderId never repeats within one instance', () async {
      final provider = InMemoryOrderIdentityProvider();
      final ids = <String>{};
      for (var i = 0; i < 50; i++) {
        final id = await provider.nextOrderId();
        ids.add(id.value);
      }
      expect(ids, hasLength(50));
    });

    test('nextOrderNumber never repeats within one instance', () async {
      final provider = InMemoryOrderIdentityProvider();
      final numbers = <String>{};
      for (var i = 0; i < 50; i++) {
        final number = await provider.nextOrderNumber();
        numbers.add(number.value);
      }
      expect(numbers, hasLength(50));
    });

    test('nextOrderId and nextOrderNumber use independent sequences', () async {
      final provider = InMemoryOrderIdentityProvider();
      final id = await provider.nextOrderId();
      final number = await provider.nextOrderNumber();

      expect(id.value, isNot(number.value));
    });

    test('two separate instances can produce the same sequence value (only unique within one runtime)', () async {
      final providerA = InMemoryOrderIdentityProvider(prefix: 'a');
      final providerB = InMemoryOrderIdentityProvider(prefix: 'b');

      final idA = await providerA.nextOrderId();
      final idB = await providerB.nextOrderId();

      // Different prefixes make them distinct here, but the point is that
      // nothing about the *sequence number* itself guarantees cross-
      // instance uniqueness — only the prefix does, and that's a test
      // convenience, not a production guarantee.
      expect(idA.value, isNot(idB.value));
      expect(idA.value, contains('-1'));
      expect(idB.value, contains('-1'));
    });
  });
}
