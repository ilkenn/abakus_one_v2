import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/application/use_cases/submit_customer_order.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../pos/test_support/fake_clock.dart';

void main() {
  group('SubmitCustomerOrder — happy path', () {
    test(
        'produces a canonical Order at pendingConfirmation with the real '
        'customerId, via the required created -> pendingConfirmation '
        'transition', () async {
      final clock = FakeClock(DateTime(2026, 8, 5, 18, 0));
      final repository = InMemoryCanonicalOrderRepository();

      final order = await SubmitCustomerOrder(
        clock: clock,
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: repository,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      ).call(
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 2),
        ],
        customerId: 'uid-abc123',
      );

      expect(order.status, OrderStatus.pendingConfirmation);
      expect(order.customerId, 'uid-abc123');
      expect(order.channel, OrderChannel.delivery);
      expect(order.branchId, 'branch-1');
      expect(order.restaurantId, 'restaurant-1');
      expect(order.lines, hasLength(1));
      expect(order.lines.single.quantity, 2);
    });

    test('customerId is null for a guest checkout — never fabricated',
        () async {
      final order = await SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 0)),
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryCanonicalOrderRepository(),
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      ).call(
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        customerId: null,
      );

      expect(order.customerId, isNull);
    });

    test('the delivery fee and order-level discount are reflected in pricing',
        () async {
      final order = await SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 0)),
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryCanonicalOrderRepository(),
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      ).call(
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        customerId: 'uid-1',
        deliveryFee: Money.fromWhole(29, Currency.tryLira),
        orderLevelDiscount: Money.fromWhole(10, Currency.tryLira),
      );

      expect(order.pricing.deliveryFee, Money.fromWhole(29, Currency.tryLira));
      expect(order.pricing.discount, Money.fromWhole(10, Currency.tryLira));
    });

    test('the checkout-preferences note is preserved as customerNote',
        () async {
      final order = await SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 0)),
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryCanonicalOrderRepository(),
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      ).call(
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        customerId: 'uid-1',
        customerNote: 'Zil çalınsın • Kapıya bırak: Kapının önü',
      );

      expect(order.customerNote, 'Zil çalınsın • Kapıya bırak: Kapının önü');
    });

    test('an empty cart throws EmptyOrderViolation', () async {
      await expectLater(
        SubmitCustomerOrder(
          clock: FakeClock(DateTime(2026, 8, 5, 18, 0)),
          identityProvider: InMemoryOrderIdentityProvider(),
          repository: InMemoryCanonicalOrderRepository(),
          branchId: 'branch-1',
          restaurantId: 'restaurant-1',
        ).call(cartItems: const [], customerId: 'uid-1'),
        throwsA(isA<EmptyOrderViolation>()),
      );
    });

    test('persists the order via the repository, retrievable by findById',
        () async {
      final repository = InMemoryCanonicalOrderRepository();
      final order = await SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 0)),
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: repository,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      ).call(
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        customerId: 'uid-1',
      );

      expect(await repository.findById(order.id), order);
      expect(await repository.findByCustomerId('uid-1'), [order]);
    });
  });
}
