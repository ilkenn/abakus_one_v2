import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/application/use_cases/submit_customer_order.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/pickup_mode.dart';
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

  group('SubmitCustomerOrder — dine-in QR (Masada Sipariş)', () {
    test(
      'passes channel/tableId/tableSessionId/guestSessionId straight '
      'through onto the canonical Order',
      () async {
        final order = await SubmitCustomerOrder(
          clock: FakeClock(DateTime(2026, 8, 5, 18, 0)),
          identityProvider: InMemoryOrderIdentityProvider(),
          repository: InMemoryCanonicalOrderRepository(),
          branchId: 'branch-1',
          restaurantId: 'restaurant-1',
        ).call(
          cartItems: const [
            CartItem(
              id: 'p1',
              name: 'Bowl',
              desc: '',
              price: 100.0,
              quantity: 1,
            ),
          ],
          customerId: null,
          channel: OrderChannel.dineInQr,
          tableId: 'dev-table-12',
          tableSessionId: 'tsession-1',
          guestSessionId: 'gsession-1',
        );

        expect(order.channel, OrderChannel.dineInQr);
        expect(order.tableId, 'dev-table-12');
        expect(order.tableSessionId, 'tsession-1');
        expect(order.guestSessionId, 'gsession-1');
        // A guest QR visit may be anonymous — customerId must not be
        // fabricated just because a table context exists.
        expect(order.customerId, isNull);
      },
    );

    test(
      'a delivery-channel order (the default) never carries table fields',
      () async {
        final order = await SubmitCustomerOrder(
          clock: FakeClock(DateTime(2026, 8, 5, 18, 0)),
          identityProvider: InMemoryOrderIdentityProvider(),
          repository: InMemoryCanonicalOrderRepository(),
          branchId: 'branch-1',
          restaurantId: 'restaurant-1',
        ).call(
          cartItems: const [
            CartItem(
              id: 'p1',
              name: 'Bowl',
              desc: '',
              price: 100.0,
              quantity: 1,
            ),
          ],
          customerId: 'uid-1',
        );

        expect(order.channel, OrderChannel.delivery);
        expect(order.tableId, isNull);
        expect(order.tableSessionId, isNull);
        expect(order.guestSessionId, isNull);
      },
    );
  });

  group('SubmitCustomerOrder — branch/restaurant call-time override, Faz B',
      () {
    test(
        'omitting branchId/restaurantId at call time keeps the constructor '
        'default — existing callers are byte-for-byte unaffected', () async {
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
      );

      expect(order.branchId, 'branch-1');
      expect(order.restaurantId, 'restaurant-1');
    });

    test('a call-time branchId/restaurantId overrides the constructor default',
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
        branchId: 'branch-ortakoy',
        restaurantId: 'restaurant-abakus',
      );

      expect(order.branchId, 'branch-ortakoy');
      expect(order.restaurantId, 'restaurant-abakus');
    });

    test('overriding only branchId leaves restaurantId on the default',
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
        channel: OrderChannel.dineInQr,
        branchId: 'branch-ortakoy',
      );

      expect(order.branchId, 'branch-ortakoy');
      expect(order.restaurantId, 'restaurant-1');
    });
  });

  group('SubmitCustomerOrder — Gel Al (takeaway) fields, Faz B', () {
    test(
        'passes takeaway pickup/contact fields straight through onto the '
        'canonical Order', () async {
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
        channel: OrderChannel.takeaway,
        takeawayEntrySessionId: 'session-1',
        pickupMode: PickupMode.asap,
        contactFirstName: 'Ada',
        contactLastName: 'Yılmaz',
        contactPhone: '+905551112233',
      );

      expect(order.channel, OrderChannel.takeaway);
      expect(order.takeawayEntrySessionId, 'session-1');
      expect(order.pickupMode, PickupMode.asap);
      expect(order.contactFirstName, 'Ada');
      expect(order.contactLastName, 'Yılmaz');
      expect(order.contactPhone, '+905551112233');
    });
  });

  group(
      'SubmitCustomerOrder — idempotency via orderId/orderNumber override, '
      'Faz C', () {
    test(
        'omitting orderId/orderNumber mints a fresh identity every call '
        '(existing behavior unchanged)', () async {
      final useCase = SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 0)),
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryCanonicalOrderRepository(),
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      );
      final cartItems = [
        const CartItem(
            id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
      ];

      final first =
          await useCase.call(cartItems: cartItems, customerId: 'uid-1');
      final second =
          await useCase.call(cartItems: cartItems, customerId: 'uid-1');

      expect(first.id.value, isNot(second.id.value));
    });

    test(
        'a caller-supplied orderId/orderNumber is used verbatim instead of '
        'minting a new one', () async {
      final orderId = OrderId('stable-order-1');
      final orderNumber = OrderNumber('STABLE-0001');

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
        orderId: orderId,
        orderNumber: orderNumber,
      );

      expect(order.id.value, 'stable-order-1');
      expect(order.orderNumber.value, 'STABLE-0001');
    });

    test(
        'retrying with the same pre-generated orderId is idempotent at the '
        'repository — a "same submission key" retry overwrites the same '
        'document instead of creating a second order', () async {
      final orderId = OrderId('stable-order-2');
      final orderNumber = OrderNumber('STABLE-0002');
      final repository = InMemoryCanonicalOrderRepository();
      final useCase = SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 0)),
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: repository,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      );
      final cartItems = [
        const CartItem(
            id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
      ];

      // Simulates a double-tap/retry: the same pre-generated identity is
      // submitted twice, exactly as `TakeawayCheckoutScreen` reuses its
      // cached `_pendingOrderId`/`_pendingOrderNumber` across attempts.
      await useCase.call(
        cartItems: cartItems,
        customerId: 'uid-1',
        orderId: orderId,
        orderNumber: orderNumber,
      );
      await useCase.call(
        cartItems: cartItems,
        customerId: 'uid-1',
        orderId: orderId,
        orderNumber: orderNumber,
      );

      final all = await repository.findAll();
      expect(all, hasLength(1));
      expect(all.single.id.value, 'stable-order-2');
    });
  });
}
