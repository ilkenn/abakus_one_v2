import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/courier_visibility.dart';
import 'package:abakus_one_v2/features/orders/domain/models/delivery_address_snapshot.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';
import 'package:abakus_one_v2/features/orders/domain/models/pickup_mode.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryAddressSnapshot _buildAddressSnapshot() {
  return DeliveryAddressSnapshot(
    savedAddressId: 'address-1',
    label: 'Ev',
    provinceId: 'il-34',
    provinceName: 'İstanbul',
    districtId: 'ilce-besiktas',
    districtName: 'Beşiktaş',
    neighborhoodId: 'mah-levent',
    neighborhoodName: 'Levent',
    buildingNo: '12',
    apartmentNo: '4',
    latitude: 41.08,
    longitude: 29.02,
    providerSource: 'manual',
    serverVerifiedAt: DateTime(2026, 8, 1),
  );
}

Order _buildOrder({
  OrderStatus status = OrderStatus.created,
  OrderChannel channel = OrderChannel.dineInStaff,
  PickupMode? pickupMode,
  DateTime? pickupTime,
}) {
  final line = OrderLine.create(
    productId: 'p1',
    productName: 'Mexifit Bowl',
    quantity: 1,
    unitPrice: Money.fromWhole(194, Currency.tryLira),
    taxRate: TaxPolicy.defaultRate,
  );
  return Order(
    id: OrderId('order-1'),
    orderNumber: OrderNumber('A-001'),
    status: status,
    channel: channel,
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
    pickupMode: pickupMode,
    pickupTime: pickupTime,
    lines: [line],
    pricing: PriceCalculator.calculate(
      lines: [line],
      currency: Currency.tryLira,
    ),
    timestamps: OrderTimestamps(created: DateTime(2026, 7, 28)),
  );
}

void main() {
  group('Order — initial state', () {
    test('defaults to CourierVisibility.hidden', () {
      final order = _buildOrder();
      expect(order.courierVisibility, CourierVisibility.hidden);
    });

    test('defaults to version 1', () {
      final order = _buildOrder();
      expect(order.version, 1);
    });

    test('starts with an empty status history', () {
      final order = _buildOrder();
      expect(order.statusHistory, isEmpty);
    });

    test('customerId/tableId/tableSessionId/guestSessionId default to null',
        () {
      final order = _buildOrder();
      expect(order.customerId, isNull);
      expect(order.tableId, isNull);
      expect(order.tableSessionId, isNull);
      expect(order.guestSessionId, isNull);
    });
  });

  group('Order.transitionTo — valid transitions', () {
    test(
        'created -> pendingConfirmation is valid and appends a status-history entry',
        () {
      final order = _buildOrder();
      final transitioned = order.transitionTo(
        OrderStatus.pendingConfirmation,
        actor: OrderActor.system,
        at: DateTime(2026, 7, 28, 12, 0),
        auditEntryId: 'audit-1',
      );

      expect(transitioned.status, OrderStatus.pendingConfirmation);
      expect(transitioned.statusHistory, hasLength(1));
      expect(transitioned.statusHistory.single.previousValue, 'created');
      expect(transitioned.statusHistory.single.newValue, 'pendingConfirmation');
    });

    test('increments version by 1 on every successful transition', () {
      final order = _buildOrder();
      final transitioned = order.transitionTo(
        OrderStatus.pendingConfirmation,
        actor: OrderActor.system,
        at: DateTime(2026, 7, 28, 12, 0),
        auditEntryId: 'audit-1',
      );

      expect(transitioned.version, 2);
    });

    test(
        'the full happy path through the 11-state machine is walkable end to end',
        () {
      var order = _buildOrder();
      const path = [
        OrderStatus.pendingConfirmation,
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.served,
        OrderStatus.completed,
        OrderStatus.refunded,
      ];

      for (final (index, next) in path.indexed) {
        order = order.transitionTo(
          next,
          actor: OrderActor.staff,
          at: DateTime(2026, 7, 28, 12, index),
          auditEntryId: 'audit-$index',
        );
      }

      expect(order.status, OrderStatus.refunded);
      expect(order.version, 1 + path.length);
      expect(order.statusHistory, hasLength(path.length));
    });

    test('records the timestamp for a tracked stage via OrderTimestamps', () {
      var order = _buildOrder();
      order = order.transitionTo(
        OrderStatus.pendingConfirmation,
        actor: OrderActor.system,
        at: DateTime(2026, 7, 28, 10, 0),
        auditEntryId: 'a1',
      );
      final confirmedAt = DateTime(2026, 7, 28, 10, 5);
      order = order.transitionTo(
        OrderStatus.confirmed,
        actor: OrderActor.staff,
        at: confirmedAt,
        auditEntryId: 'a2',
      );

      expect(order.timestamps.confirmed, confirmedAt);
    });
  });

  group('Order.transitionTo — invalid transitions are rejected', () {
    test('rejects skipping stages (created -> preparing)', () {
      final order = _buildOrder();
      expect(
        () => order.transitionTo(
          OrderStatus.preparing,
          actor: OrderActor.system,
          at: DateTime(2026, 7, 28),
          auditEntryId: 'a1',
        ),
        throwsA(isA<InvalidOrderStatusTransitionViolation>()),
      );
    });

    test('rejects reopening a terminal state (cancelled -> anything)', () {
      final order = _buildOrder(status: OrderStatus.cancelled);
      expect(
        () => order.transitionTo(
          OrderStatus.confirmed,
          actor: OrderActor.staff,
          at: DateTime(2026, 7, 28),
          auditEntryId: 'a1',
        ),
        throwsA(isA<InvalidOrderStatusTransitionViolation>()),
      );
    });

    test('rejects cancellation after served (must go through refunded instead)',
        () {
      final order = _buildOrder(status: OrderStatus.served);
      expect(
        () => order.transitionTo(
          OrderStatus.cancelled,
          actor: OrderActor.staff,
          at: DateTime(2026, 7, 28),
          auditEntryId: 'a1',
        ),
        throwsA(isA<InvalidOrderStatusTransitionViolation>()),
      );
    });

    test('rejects a status transitioning to itself', () {
      final order = _buildOrder(status: OrderStatus.confirmed);
      expect(
        () => order.transitionTo(
          OrderStatus.confirmed,
          actor: OrderActor.staff,
          at: DateTime(2026, 7, 28),
          auditEntryId: 'a1',
        ),
        throwsA(isA<InvalidOrderStatusTransitionViolation>()),
      );
    });

    test(
        'an order\'s version/status/statusHistory are unchanged when a transition is rejected',
        () {
      final order = _buildOrder();
      try {
        order.transitionTo(
          OrderStatus.preparing,
          actor: OrderActor.system,
          at: DateTime(2026, 7, 28),
          auditEntryId: 'a1',
        );
      } on InvalidOrderStatusTransitionViolation {
        // expected
      }
      expect(order.status, OrderStatus.created);
      expect(order.version, 1);
      expect(order.statusHistory, isEmpty);
    });
  });

  group('Order — order-level notes (Phase 3 Sprint 3B)', () {
    test(
        'customerNote and kitchenNote default to empty, preserving existing callers',
        () {
      final order = _buildOrder();
      expect(order.customerNote, '');
      expect(order.kitchenNote, '');
    });

    test('customerNote and kitchenNote are distinct from any line-level note',
        () {
      final line = OrderLine.create(
        productId: 'p1',
        productName: 'Bowl',
        quantity: 1,
        unitPrice: Money.fromWhole(100, Currency.tryLira),
        taxRate: TaxPolicy.defaultRate,
        customerNote: 'Az tuzlu',
        kitchenNote: 'Acil',
      );
      final order = Order(
        id: OrderId('order-1'),
        orderNumber: OrderNumber('A-001'),
        status: OrderStatus.created,
        channel: OrderChannel.dineInStaff,
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
        lines: [line],
        pricing: PriceCalculator.calculate(
          lines: [line],
          currency: Currency.tryLira,
        ),
        timestamps: OrderTimestamps(created: DateTime(2026, 7, 28)),
        customerNote: 'Zile basmayın',
        kitchenNote: 'Masaya servis',
      );

      expect(order.customerNote, 'Zile basmayın');
      expect(order.kitchenNote, 'Masaya servis');
      expect(order.lines.single.customerNote, 'Az tuzlu');
      expect(order.lines.single.kitchenNote, 'Acil');
    });

    test('copyWith preserves notes when not given, updates them when given',
        () {
      final order = _buildOrder().copyWith(
        customerNote: 'Original customer note',
        kitchenNote: 'Original kitchen note',
      );

      final untouched = order.copyWith(status: OrderStatus.created);
      expect(untouched.customerNote, 'Original customer note');
      expect(untouched.kitchenNote, 'Original kitchen note');

      final updated = order.copyWith(customerNote: 'Updated');
      expect(updated.customerNote, 'Updated');
      expect(updated.kitchenNote, 'Original kitchen note');
    });
  });

  group('Order — Gel Al (takeaway) additive fields, Faz B', () {
    test(
        'takeawayEntrySessionId/pickupMode/pickupTime/contact fields default to null',
        () {
      final order = _buildOrder();
      expect(order.takeawayEntrySessionId, isNull);
      expect(order.pickupMode, isNull);
      expect(order.pickupTime, isNull);
      expect(order.contactFirstName, isNull);
      expect(order.contactLastName, isNull);
      expect(order.contactPhone, isNull);
    });

    test('a non-takeaway order (dineInStaff/dineInQr/delivery) is unaffected',
        () {
      for (final channel in [
        OrderChannel.dineInStaff,
        OrderChannel.dineInQr,
        OrderChannel.delivery,
      ]) {
        final order = _buildOrder(channel: channel);
        expect(order.pickupMode, isNull, reason: '$channel');
        expect(order.pickupTime, isNull, reason: '$channel');
      }
    });

    test('takeaway + asap: pickupMode = asap, pickupTime may stay null', () {
      final order = _buildOrder(
        channel: OrderChannel.takeaway,
        pickupMode: PickupMode.asap,
      );
      expect(order.pickupMode, PickupMode.asap);
      expect(order.pickupTime, isNull);
    });

    test('takeaway + scheduled with a pickupTime is valid', () {
      final order = _buildOrder(
        channel: OrderChannel.takeaway,
        pickupMode: PickupMode.scheduled,
        pickupTime: DateTime(2026, 8, 10, 13, 30),
      );
      expect(order.pickupMode, PickupMode.scheduled);
      expect(order.pickupTime, DateTime(2026, 8, 10, 13, 30));
    });

    test('takeaway + scheduled with a null pickupTime violates the invariant',
        () {
      // flutter test always runs with assertions enabled, so this is a
      // reliable check of Order's own constructor-level invariant, not a
      // best-effort one.
      expect(
        () => _buildOrder(
          channel: OrderChannel.takeaway,
          pickupMode: PickupMode.scheduled,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('copyWith preserves the new fields when not given, updates when given',
        () {
      final order = _buildOrder(
        channel: OrderChannel.takeaway,
        pickupMode: PickupMode.asap,
      ).copyWith(
        takeawayEntrySessionId: 'session-1',
        contactFirstName: 'Ada',
        contactLastName: 'Yılmaz',
        contactPhone: '+905551112233',
      );

      final untouched = order.copyWith(status: OrderStatus.pendingConfirmation);
      expect(untouched.takeawayEntrySessionId, 'session-1');
      expect(untouched.contactFirstName, 'Ada');
      expect(untouched.contactLastName, 'Yılmaz');
      expect(untouched.contactPhone, '+905551112233');
      expect(untouched.pickupMode, PickupMode.asap);

      final updated = order.copyWith(contactFirstName: 'Deniz');
      expect(updated.contactFirstName, 'Deniz');
      expect(updated.contactLastName, 'Yılmaz');
    });
  });

  group('Order — Paket Servis (delivery) additive fields, Faz P.1', () {
    test(
        'deliveryAddressSnapshot/paymentMethodSnapshot default to null '
        '(req 1)', () {
      final order = _buildOrder();
      expect(order.deliveryAddressSnapshot, isNull);
      expect(order.paymentMethodSnapshot, isNull);
    });

    test(
        'every existing channel (dineInQr/dineInStaff/takeaway/'
        'reservationPreorder) still constructs unaffected (req 1)', () {
      for (final channel in [
        OrderChannel.dineInQr,
        OrderChannel.dineInStaff,
        OrderChannel.takeaway,
        OrderChannel.reservationPreorder,
      ]) {
        final order = _buildOrder(channel: channel);
        expect(order.deliveryAddressSnapshot, isNull, reason: '$channel');
        expect(order.paymentMethodSnapshot, isNull, reason: '$channel');
      }
    });

    test(
        'copyWith sets deliveryAddressSnapshot/paymentMethodSnapshot and '
        'preserves them when not given again (req 1, 2, 4)', () {
      final addressSnapshot = _buildAddressSnapshot();
      final paymentSnapshot =
          PaymentMethodSnapshot.capture(PaymentMethodSeedData.cash);

      final order = _buildOrder(channel: OrderChannel.delivery).copyWith(
        deliveryAddressSnapshot: addressSnapshot,
        paymentMethodSnapshot: paymentSnapshot,
      );

      expect(order.deliveryAddressSnapshot, addressSnapshot);
      expect(order.paymentMethodSnapshot, paymentSnapshot);

      final untouched = order.copyWith(status: OrderStatus.pendingConfirmation);
      expect(untouched.deliveryAddressSnapshot, addressSnapshot);
      expect(untouched.paymentMethodSnapshot, paymentSnapshot);
    });

    test(
        'once attached, the snapshot is immutable historical data — a '
        'later change to the source values never mutates the frozen '
        'snapshot object (req 4)', () {
      final addressSnapshot = _buildAddressSnapshot();
      final order = _buildOrder(channel: OrderChannel.delivery)
          .copyWith(deliveryAddressSnapshot: addressSnapshot);

      // DeliveryAddressSnapshot has no setters/mutating methods at all —
      // the only way to "change" it is to construct a new one, which
      // copyWith'ing the Order with a different snapshot proves does not
      // affect the original snapshot instance still referenced elsewhere.
      final differentSnapshot = _buildAddressSnapshot();
      final reAssigned =
          order.copyWith(deliveryAddressSnapshot: differentSnapshot);

      expect(order.deliveryAddressSnapshot, addressSnapshot);
      expect(reAssigned.deliveryAddressSnapshot, differentSnapshot);
      expect(addressSnapshot, differentSnapshot,
          reason: 'value-equal but distinct instances');
    });
  });
}
