import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/application/use_cases/submit_customer_order.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/data/order_firestore_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

void main() {
  group('OrderFirestoreMapper round-trip', () {
    test(
        'toFirestore/fromFirestore preserves every field a real order '
        'carries', () async {
      final order = await SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 30)),
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryCanonicalOrderRepository(),
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      ).call(
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 2),
        ],
        customerId: 'uid-abc123',
        deliveryFee: Money.fromWhole(29, Currency.tryLira),
        orderLevelDiscount: Money.fromWhole(10, Currency.tryLira),
        customerNote: 'Zil çalınsın',
      );

      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');
      // Simulates the JSON round-trip a real Firestore write/read would
      // go through — nested maps come back as Map<Object?, Object?>, not
      // the original Map<String, dynamic>.
      final restored = OrderFirestoreMapper.fromFirestore(
        Map<String, dynamic>.from(data),
      );

      expect(data['organizationId'], 'org-1');
      expect(restored.id.value, order.id.value);
      expect(restored.orderNumber.value, order.orderNumber.value);
      expect(restored.status, order.status);
      expect(restored.channel, order.channel);
      expect(restored.branchId, order.branchId);
      expect(restored.restaurantId, order.restaurantId);
      expect(restored.customerId, order.customerId);
      expect(restored.courierVisibility, order.courierVisibility);
      expect(restored.version, order.version);
      expect(restored.customerNote, order.customerNote);

      expect(restored.lines, hasLength(order.lines.length));
      expect(restored.lines.single.productId, order.lines.single.productId);
      expect(restored.lines.single.quantity, order.lines.single.quantity);
      expect(restored.lines.single.unitPrice, order.lines.single.unitPrice);
      expect(restored.lines.single.lineTotal, order.lines.single.lineTotal);
      expect(restored.lines.single.tax.rate, order.lines.single.tax.rate);

      expect(restored.pricing.grandTotal, order.pricing.grandTotal);
      expect(restored.pricing.deliveryFee, order.pricing.deliveryFee);
      expect(restored.pricing.discount, order.pricing.discount);

      expect(restored.statusHistory, hasLength(order.statusHistory.length));
      expect(restored.statusHistory.single.id, order.statusHistory.single.id);
      expect(restored.statusHistory.single.actor,
          order.statusHistory.single.actor);

      expect(restored.timestamps.created, order.timestamps.created);
    });

    test('a guest order (customerId null) round-trips with customerId null',
        () async {
      final order = await SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 30)),
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

      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');
      final restored =
          OrderFirestoreMapper.fromFirestore(Map<String, dynamic>.from(data));

      expect(data['customerId'], isNull);
      expect(restored.customerId, isNull);
    });
  });
}
