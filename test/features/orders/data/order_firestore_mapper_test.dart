import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/application/use_cases/submit_customer_order.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/data/order_firestore_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/models/delivery_address_snapshot.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/pickup_mode.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

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
    streetId: 'sok-1',
    streetName: '1. Sokak',
    buildingNo: '12',
    apartmentNo: '4',
    floor: '2',
    addressDescription: 'Kapıcıya bırakın',
    latitude: 41.08,
    longitude: 29.02,
    providerSource: 'manual',
    providerPlaceId: 'place-1',
    serverVerifiedAt: DateTime(2026, 8, 1, 10, 0),
  );
}

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

    test(
        'guestAuthUid round-trips independently of customerId — Phase 3.1: '
        'set for a Table Guest Session order regardless of whether the '
        'order also carries a real customerId', () async {
      final guestOrder = await SubmitCustomerOrder(
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
        guestAuthUid: 'anon-technical-uid-1',
      );
      final guestData = OrderFirestoreMapper.toFirestore(
        guestOrder,
        organizationId: 'org-1',
      );
      final guestRestored = OrderFirestoreMapper.fromFirestore(
        Map<String, dynamic>.from(guestData),
      );

      expect(guestData['guestAuthUid'], 'anon-technical-uid-1');
      expect(guestData['customerId'], isNull);
      expect(guestRestored.guestAuthUid, 'anon-technical-uid-1');
      expect(guestRestored.customerId, isNull);

      final customerOrder = await SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 30)),
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryCanonicalOrderRepository(),
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      ).call(
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        customerId: 'real-customer-uid',
        guestAuthUid: 'real-customer-uid',
      );
      final customerData = OrderFirestoreMapper.toFirestore(
        customerOrder,
        organizationId: 'org-1',
      );
      final customerRestored = OrderFirestoreMapper.fromFirestore(
        Map<String, dynamic>.from(customerData),
      );

      expect(customerData['guestAuthUid'], 'real-customer-uid');
      expect(customerData['customerId'], 'real-customer-uid');
      expect(customerRestored.guestAuthUid, 'real-customer-uid');
      expect(customerRestored.customerId, 'real-customer-uid');
    });

    test(
        'guestAuthUid is null for a non-dineInQr order — the field has no '
        'meaning outside the Table Guest Session flow', () async {
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
        customerId: 'real-customer-uid',
      );
      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');
      final restored =
          OrderFirestoreMapper.fromFirestore(Map<String, dynamic>.from(data));

      expect(data['guestAuthUid'], isNull);
      expect(restored.guestAuthUid, isNull);
    });

    test(
        'reservationContextId round-trips independently of customerId/'
        'guestAuthUid — Faz R.1C.2: a server-generated snapshot, never an '
        'identity field', () async {
      final reservationOrder = await SubmitCustomerOrder(
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
        guestAuthUid: 'anon-technical-uid-rc',
        reservationContextId: 'RES_123',
      );
      final data = OrderFirestoreMapper.toFirestore(
        reservationOrder,
        organizationId: 'org-1',
      );
      final restored =
          OrderFirestoreMapper.fromFirestore(Map<String, dynamic>.from(data));

      expect(data['reservationContextId'], 'RES_123');
      expect(restored.reservationContextId, 'RES_123');
      // Identity fields are untouched by the presence of a reservation
      // context — it never produces or overrides customerId/guestAuthUid.
      expect(data['customerId'], isNull);
      expect(data['guestAuthUid'], 'anon-technical-uid-rc');
    });

    test(
        'reservationContextId is null for the ordinary walk-in order — the '
        'default for every existing caller that never passes it', () async {
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
        guestAuthUid: 'anon-technical-uid-walkin',
      );
      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');
      final restored =
          OrderFirestoreMapper.fromFirestore(Map<String, dynamic>.from(data));

      expect(data['reservationContextId'], isNull);
      expect(restored.reservationContextId, isNull);
    });
  });

  group('OrderFirestoreMapper — Gel Al (takeaway) fields, Faz B', () {
    test(
        'takeawayEntrySessionId/pickupMode/pickupTime/contact fields '
        'round-trip', () async {
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
        channel: OrderChannel.takeaway,
        takeawayEntrySessionId: 'session-1',
        pickupMode: PickupMode.scheduled,
        pickupTime: DateTime(2026, 8, 5, 19, 0),
        contactFirstName: 'Ada',
        contactLastName: 'Yılmaz',
        contactPhone: '+905551112233',
      );

      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');
      final restored =
          OrderFirestoreMapper.fromFirestore(Map<String, dynamic>.from(data));

      expect(data['takeawayEntrySessionId'], 'session-1');
      expect(data['pickupMode'], 'scheduled');
      expect(data['pickupTime'], isA<String>());
      expect(data['contactFirstName'], 'Ada');
      expect(data['contactLastName'], 'Yılmaz');
      expect(data['contactPhone'], '+905551112233');

      expect(restored.takeawayEntrySessionId, 'session-1');
      expect(restored.pickupMode, PickupMode.scheduled);
      expect(restored.pickupTime, DateTime(2026, 8, 5, 19, 0));
      expect(restored.contactFirstName, 'Ada');
      expect(restored.contactLastName, 'Yılmaz');
      expect(restored.contactPhone, '+905551112233');
    });

    test(
        'pickupTimeTimestamp (Faz C) carries the same instant as pickupTime, '
        'as a raw DateTime — the shape a real cloud_firestore write '
        'auto-converts to a native Timestamp, so firestore.rules can '
        'compare it against request.time; fromFirestore never reads it '
        'back, pickupTime alone remains the round-trip source of truth',
        () async {
      final pickupTime = DateTime(2026, 8, 5, 19, 0);
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
        channel: OrderChannel.takeaway,
        pickupMode: PickupMode.scheduled,
        pickupTime: pickupTime,
      );

      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');

      expect(data['pickupTimeTimestamp'], isA<DateTime>());
      expect(data['pickupTimeTimestamp'], pickupTime);
    });

    test('pickupTimeTimestamp is null when pickupTime is null', () async {
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
        customerId: 'uid-1',
      );

      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');

      expect(data['pickupTimeTimestamp'], isNull);
    });

    test('every new field is null for a non-takeaway order', () async {
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
        customerId: 'uid-1',
      );

      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');
      final restored =
          OrderFirestoreMapper.fromFirestore(Map<String, dynamic>.from(data));

      expect(data['takeawayEntrySessionId'], isNull);
      expect(data['pickupMode'], isNull);
      expect(data['pickupTime'], isNull);
      expect(restored.pickupMode, isNull);
      expect(restored.pickupTime, isNull);
    });

    test(
        'a pre-Faz-B Firestore document (no new keys at all) still '
        'deserializes — every new field reads as null, nothing throws',
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
        customerId: 'uid-1',
      );

      final legacyData =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1')
            ..remove('takeawayEntrySessionId')
            ..remove('pickupMode')
            ..remove('pickupTime')
            ..remove('contactFirstName')
            ..remove('contactLastName')
            ..remove('contactPhone');

      final restored = OrderFirestoreMapper.fromFirestore(
        Map<String, dynamic>.from(legacyData),
      );

      expect(restored.id.value, order.id.value);
      expect(restored.takeawayEntrySessionId, isNull);
      expect(restored.pickupMode, isNull);
      expect(restored.pickupTime, isNull);
      expect(restored.contactFirstName, isNull);
      expect(restored.contactLastName, isNull);
      expect(restored.contactPhone, isNull);
    });
  });

  group('OrderFirestoreMapper — Paket Servis (delivery) fields, Faz P.1', () {
    test('deliveryAddressSnapshot round-trips (req 2)', () async {
      final base = await SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 30)),
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryCanonicalOrderRepository(),
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      ).call(
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        customerId: 'uid-1',
        channel: OrderChannel.delivery,
      );
      final addressSnapshot = _buildAddressSnapshot();
      final order = base.copyWith(deliveryAddressSnapshot: addressSnapshot);

      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');
      final restored =
          OrderFirestoreMapper.fromFirestore(Map<String, dynamic>.from(data));

      expect(data['deliveryAddressSnapshot'], isA<Map>());
      final restoredSnapshot = restored.deliveryAddressSnapshot;
      expect(restoredSnapshot, isNotNull);
      expect(restoredSnapshot!.savedAddressId, addressSnapshot.savedAddressId);
      expect(restoredSnapshot.districtName, addressSnapshot.districtName);
      expect(
          restoredSnapshot.neighborhoodName, addressSnapshot.neighborhoodName);
      expect(restoredSnapshot.streetId, addressSnapshot.streetId);
      expect(restoredSnapshot.buildingNo, addressSnapshot.buildingNo);
      expect(restoredSnapshot.apartmentNo, addressSnapshot.apartmentNo);
      expect(restoredSnapshot.floor, addressSnapshot.floor);
      expect(restoredSnapshot.addressDescription,
          addressSnapshot.addressDescription);
      expect(restoredSnapshot.latitude, addressSnapshot.latitude);
      expect(restoredSnapshot.longitude, addressSnapshot.longitude);
      expect(restoredSnapshot.providerSource, addressSnapshot.providerSource);
      expect(restoredSnapshot.providerPlaceId, addressSnapshot.providerPlaceId);
      expect(
          restoredSnapshot.serverVerifiedAt, addressSnapshot.serverVerifiedAt);
      expect(restoredSnapshot, addressSnapshot);
    });

    test('paymentMethodSnapshot round-trips (req 3)', () async {
      final base = await SubmitCustomerOrder(
        clock: FakeClock(DateTime(2026, 8, 5, 18, 30)),
        identityProvider: InMemoryOrderIdentityProvider(),
        repository: InMemoryCanonicalOrderRepository(),
        branchId: 'branch-1',
        restaurantId: 'restaurant-1',
      ).call(
        cartItems: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        customerId: 'uid-1',
        channel: OrderChannel.delivery,
      );
      final paymentSnapshot =
          PaymentMethodSnapshot.capture(PaymentMethodSeedData.pluxee);
      final order = base.copyWith(paymentMethodSnapshot: paymentSnapshot);

      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');
      final restored =
          OrderFirestoreMapper.fromFirestore(Map<String, dynamic>.from(data));

      expect(data['paymentMethodSnapshot'], isA<Map>());
      final restoredSnapshot = restored.paymentMethodSnapshot;
      expect(restoredSnapshot, isNotNull);
      expect(restoredSnapshot!.paymentMethodId, 'pluxee');
      expect(restoredSnapshot.displayName, paymentSnapshot.displayName);
      expect(restoredSnapshot.reportingCategory,
          paymentSnapshot.reportingCategory);
      expect(restoredSnapshot.providerId, paymentSnapshot.providerId);
      expect(restoredSnapshot, paymentSnapshot);
    });

    test('both new fields are null for an order that never set them (req 1)',
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
        customerId: 'uid-1',
      );

      final data =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1');
      final restored =
          OrderFirestoreMapper.fromFirestore(Map<String, dynamic>.from(data));

      expect(data['deliveryAddressSnapshot'], isNull);
      expect(data['paymentMethodSnapshot'], isNull);
      expect(restored.deliveryAddressSnapshot, isNull);
      expect(restored.paymentMethodSnapshot, isNull);
    });

    test(
        'a pre-Faz-P.1 Firestore document (no new keys at all) still '
        'deserializes with null snapshots, nothing throws (req 1)', () async {
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
        customerId: 'uid-1',
      );

      final legacyData =
          OrderFirestoreMapper.toFirestore(order, organizationId: 'org-1')
            ..remove('deliveryAddressSnapshot')
            ..remove('paymentMethodSnapshot');

      final restored = OrderFirestoreMapper.fromFirestore(
        Map<String, dynamic>.from(legacyData),
      );

      expect(restored.id.value, order.id.value);
      expect(restored.deliveryAddressSnapshot, isNull);
      expect(restored.paymentMethodSnapshot, isNull);
    });
  });
}
