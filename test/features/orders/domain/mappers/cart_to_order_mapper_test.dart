import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/menu/domain/models/selected_modifier.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/courier_visibility.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/pickup_mode.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CartToOrderMapper.map — snapshot fidelity', () {
    test(
        'freezes product name, price, and modifiers from the cart at mapping time',
        () {
      final sourceModifiers = <SelectedModifier>[
        const SelectedModifier(
          groupId: 'protein',
          groupName: 'Protein',
          optionId: 'chicken',
          optionName: 'Izgara Tavuk',
          extraPrice: 40.0,
        ),
      ];
      final cartItems = [
        CartItem(
          id: 'prod_mexifit_bowl',
          name: 'Mexifit Bowl',
          desc: '',
          price: 194.0,
          quantity: 1,
          selectedModifiers: sourceModifiers,
        ),
      ];

      final order = CartToOrderMapper.map(
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: cartItems,
        channel: OrderChannel.dineInStaff,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 28, 12, 0),
      );

      final line = order.lines.single;
      expect(line.productId, 'prod_mexifit_bowl');
      expect(line.productName, 'Mexifit Bowl');
      expect(line.unitPrice, Money.fromWhole(194, Currency.tryLira));
      expect(line.modifiers.single.optionName, 'Izgara Tavuk');
      expect(
        line.modifiers.single.unitExtraPrice,
        Money.fromWhole(40, Currency.tryLira),
      );

      // Later mutation of the source list must never alter the already-built
      // order — the mapper must have copied, not referenced, the modifiers.
      sourceModifiers.clear();
      expect(order.lines.single.modifiers, hasLength(1));
    });

    test(
        'freezes legacy protein/sauce/extras/removed fields as kitchen note text',
        () {
      final cartItems = [
        const CartItem(
          id: 'p1',
          name: 'Custom Bowl',
          desc: '',
          price: 200.0,
          quantity: 1,
          selectedProtein: 'Tavuk',
          selectedSauce: 'Acı Sos',
          extraIngredients: ['Avokado'],
          removedIngredients: ['Soğan'],
        ),
      ];

      final order = CartToOrderMapper.map(
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: cartItems,
        channel: OrderChannel.takeaway,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 28),
      );

      final note = order.lines.single.kitchenNote;
      expect(note, contains('Protein: Tavuk'));
      expect(note, contains('Sos: Acı Sos'));
      expect(note, contains('Ekstra: Avokado'));
      expect(note, contains('Çıkarılan: Soğan'));
    });

    test('freezes the customer note separately from the kitchen note', () {
      final cartItems = [
        const CartItem(
          id: 'p1',
          name: 'Bowl',
          desc: '',
          price: 100.0,
          quantity: 1,
          note: 'Az tuzlu olsun lütfen',
        ),
      ];

      final order = CartToOrderMapper.map(
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: cartItems,
        channel: OrderChannel.dineInQr,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 28),
      );

      expect(order.lines.single.customerNote, 'Az tuzlu olsun lütfen');
    });

    test('folds extraCostPerUnit into the line\'s unitPrice', () {
      final cartItems = [
        const CartItem(
          id: 'p1',
          name: 'Bowl',
          desc: '',
          price: 100.0,
          quantity: 1,
          extraCostPerUnit: 15.0,
        ),
      ];

      final order = CartToOrderMapper.map(
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: cartItems,
        channel: OrderChannel.takeaway,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 28),
      );

      expect(
        order.lines.single.unitPrice,
        Money.fromWhole(115, Currency.tryLira),
      );
    });

    test(
        'snapshots the tax rate on each line, independent of a later TaxPolicy change',
        () {
      final cartItems = [
        const CartItem(
            id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
      ];
      final order = CartToOrderMapper.map(
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: cartItems,
        channel: OrderChannel.takeaway,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 28),
      );

      expect(order.lines.single.tax.rate, TaxPolicy.defaultRate);
    });
  });

  group('CartToOrderMapper.map — order-level notes (Phase 3 Sprint 3B)', () {
    test(
        'snapshots customerNote and kitchenNote onto the Order, defaulting to empty',
        () {
      final cartItems = [
        const CartItem(
            id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
      ];

      final withoutNotes = CartToOrderMapper.map(
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: cartItems,
        channel: OrderChannel.takeaway,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 28),
      );
      expect(withoutNotes.customerNote, '');
      expect(withoutNotes.kitchenNote, '');

      final withNotes = CartToOrderMapper.map(
        orderId: OrderId('order-2'),
        orderNumber: OrderNumber('A-002'),
        cartItems: cartItems,
        channel: OrderChannel.takeaway,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 28),
        customerNote: 'Zile basmayın',
        kitchenNote: 'Acil hazırlansın',
      );
      expect(withNotes.customerNote, 'Zile basmayın');
      expect(withNotes.kitchenNote, 'Acil hazırlansın');
    });
  });

  group('CartToOrderMapper.map — validation', () {
    test('rejects an empty cart', () {
      expect(
        () => CartToOrderMapper.map(
          orderId: OrderId('order-1'),
          orderNumber: OrderNumber('A-001'),
          cartItems: const [],
          channel: OrderChannel.takeaway,
          branchId: 'branch-1',
          restaurantId: 'restaurant-1',
          now: DateTime(2026, 7, 28),
        ),
        throwsA(isA<EmptyOrderViolation>()),
      );
    });
  });

  group('CartToOrderMapper.map — Gel Al (takeaway) fields, Faz B', () {
    test('threads takeaway pickup/contact fields through onto the Order', () {
      final cartItems = [
        const CartItem(
            id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
      ];

      final order = CartToOrderMapper.map(
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: cartItems,
        channel: OrderChannel.takeaway,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 28),
        takeawayEntrySessionId: 'session-1',
        pickupMode: PickupMode.scheduled,
        pickupTime: DateTime(2026, 7, 28, 13, 20),
        contactFirstName: 'Ada',
        contactLastName: 'Yılmaz',
        contactPhone: '+905551112233',
      );

      expect(order.takeawayEntrySessionId, 'session-1');
      expect(order.pickupMode, PickupMode.scheduled);
      expect(order.pickupTime, DateTime(2026, 7, 28, 13, 20));
      expect(order.contactFirstName, 'Ada');
      expect(order.contactLastName, 'Yılmaz');
      expect(order.contactPhone, '+905551112233');
    });

    test(
        'every new field defaults to null when omitted (existing callers unaffected)',
        () {
      final cartItems = [
        const CartItem(
            id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
      ];

      final order = CartToOrderMapper.map(
        orderId: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: cartItems,
        channel: OrderChannel.dineInStaff,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        now: DateTime(2026, 7, 28),
      );

      expect(order.takeawayEntrySessionId, isNull);
      expect(order.pickupMode, isNull);
      expect(order.pickupTime, isNull);
      expect(order.contactFirstName, isNull);
      expect(order.contactLastName, isNull);
      expect(order.contactPhone, isNull);
    });
  });

  group('Complete POS order-creation scenario', () {
    test(
        'a staff-created dine-in order: cart -> Order -> confirmed -> preparing, with fees and a discount',
        () {
      // A cashier at the POS adds two items to a table's cart.
      final cartItems = [
        const CartItem(
          id: 'prod_mexifit_bowl',
          name: 'Mexifit Bowl',
          desc: 'Meksika esintili bowl',
          price: 194.0,
          quantity: 2,
          selectedModifiers: [
            SelectedModifier(
              groupId: 'protein',
              groupName: 'Protein',
              optionId: 'chicken',
              optionName: 'Izgara Tavuk',
              extraPrice: 40.0,
            ),
          ],
          note: 'Sosu ayrı gelsin',
        ),
        const CartItem(
          id: 'prod_ayran',
          name: 'Ayran',
          desc: '',
          price: 25.0,
          quantity: 2,
        ),
      ];

      // The cashier checks the order out at the POS — this is the
      // cart-to-order boundary.
      final order = CartToOrderMapper.map(
        orderId: OrderId('order-pos-1'),
        orderNumber: OrderNumber('A-001'),
        cartItems: cartItems,
        channel: OrderChannel.dineInStaff,
        branchId: 'branch-ortakoy',
        restaurantId: 'restaurant-abakus',
        tableId: 'table-12',
        serviceFee: Money.fromWhole(10, Currency.tryLira),
        orderLevelDiscount: Money.fromWhole(20, Currency.tryLira),
        now: DateTime(2026, 7, 28, 13, 0),
      );

      // Order aggregate identity and channel/table context.
      expect(order.status, OrderStatus.created);
      expect(order.channel, OrderChannel.dineInStaff);
      expect(order.tableId, 'table-12');
      expect(order.courierVisibility, CourierVisibility.hidden);
      expect(order.version, 1);

      // Pricing: (194+40)*2 + 25*2 = 468 + 50 = 518 gross subtotal;
      // - 20 discount + 10 service fee = 508 grand total.
      expect(
          order.pricing.grossSubtotal, Money.fromWhole(518, Currency.tryLira));
      expect(order.pricing.discount, Money.fromWhole(20, Currency.tryLira));
      expect(order.pricing.serviceFee, Money.fromWhole(10, Currency.tryLira));
      expect(order.pricing.grandTotal, Money.fromWhole(508, Currency.tryLira));
      expect(order.pricing.taxableBase + order.pricing.vatAmount,
          order.pricing.grossSubtotal);

      // The order is accepted (no stage-skipping — created must pass
      // through pendingConfirmation before confirmed), the cashier confirms
      // it at the till, then the kitchen starts preparing it.
      final pending = order.transitionTo(
        OrderStatus.pendingConfirmation,
        actor: OrderActor.system,
        at: DateTime(2026, 7, 28, 13, 1),
        auditEntryId: 'audit-1',
      );
      final confirmed = pending.transitionTo(
        OrderStatus.confirmed,
        actor: OrderActor.staff,
        at: DateTime(2026, 7, 28, 13, 2),
        auditEntryId: 'audit-2',
      );
      final preparing = confirmed.transitionTo(
        OrderStatus.preparing,
        actor: OrderActor.kitchen,
        at: DateTime(2026, 7, 28, 13, 3),
        auditEntryId: 'audit-3',
      );

      expect(preparing.status, OrderStatus.preparing);
      expect(preparing.version, 4);
      expect(preparing.statusHistory, hasLength(3));
      expect(preparing.statusHistory[0].actor, OrderActor.system);
      expect(preparing.statusHistory[1].actor, OrderActor.staff);
      expect(preparing.statusHistory[2].actor, OrderActor.kitchen);

      // An out-of-order jump (e.g. straight to served) is still rejected
      // for this POS-created order, exactly as for any other channel.
      expect(
        () => preparing.transitionTo(
          OrderStatus.served,
          actor: OrderActor.staff,
          at: DateTime(2026, 7, 28, 13, 3),
          auditEntryId: 'audit-3',
        ),
        throwsA(isA<InvalidOrderStatusTransitionViolation>()),
      );
    });
  });
}
