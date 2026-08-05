import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/application/use_cases/submit_customer_order.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/data/order_firestore_client.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

/// A deterministic, in-memory [OrderFirestoreClient] fake — no real
/// Firestore SDK involved.
class _FakeOrderFirestoreClient implements OrderFirestoreClient {
  final Map<String, Map<String, dynamic>> _byId = {};

  @override
  Future<void> setOrder(String orderId, Map<String, dynamic> data) async {
    _byId[orderId] = data;
  }

  @override
  Future<Map<String, dynamic>?> getOrder(String orderId) async =>
      _byId[orderId];

  @override
  Future<List<Map<String, dynamic>>> queryOrdersByCustomerId(
      String customerId) async {
    return [
      for (final data in _byId.values)
        if (data['customerId'] == customerId) data,
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getAllOrders() async =>
      List.unmodifiable(_byId.values);
}

/// [idPrefix] distinguishes orders built by separate calls — each call
/// constructs its own fresh [InMemoryOrderIdentityProvider], which starts
/// its own sequence back at 1 per instance (see its own doc comment); two
/// orders in the same test would otherwise collide on the same id and
/// silently overwrite each other in [_FakeOrderFirestoreClient]'s
/// id-keyed map.
Future<Order> _buildOrder({
  String? customerId = 'uid-1',
  String idPrefix = 'test',
}) {
  return SubmitCustomerOrder(
    clock: FakeClock(DateTime(2026, 8, 5, 18, 30)),
    identityProvider: InMemoryOrderIdentityProvider(prefix: idPrefix),
    repository: InMemoryCanonicalOrderRepository(),
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
  ).call(
    cartItems: const [
      CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
    ],
    customerId: customerId,
  );
}

void main() {
  group('FirestoreCanonicalOrderRepository', () {
    test(
        'submitOrder resolves and denormalizes organizationId via the '
        'injected restaurant→organization closure', () async {
      final client = _FakeOrderFirestoreClient();
      final repository = FirestoreCanonicalOrderRepository(
        client: client,
        resolveOrganizationId: (restaurantId) async => 'org-1',
      );
      final order = await _buildOrder();

      await repository.submitOrder(order);

      final stored = await client.getOrder(order.id.value);
      expect(stored, isNotNull);
      expect(stored!['organizationId'], 'org-1');
    });

    test(
        'submitOrder fails closed — throws, never persists — when the '
        'restaurant cannot be resolved to an organization', () async {
      final client = _FakeOrderFirestoreClient();
      final repository = FirestoreCanonicalOrderRepository(
        client: client,
        resolveOrganizationId: (restaurantId) async => null,
      );
      final order = await _buildOrder();

      await expectLater(
        repository.submitOrder(order),
        throwsA(isA<StateError>()),
      );
      expect(await client.getOrder(order.id.value), isNull);
    });

    test('findById returns the persisted order, converted back correctly',
        () async {
      final client = _FakeOrderFirestoreClient();
      final repository = FirestoreCanonicalOrderRepository(
        client: client,
        resolveOrganizationId: (restaurantId) async => 'org-1',
      );
      final order = await _buildOrder();
      await repository.submitOrder(order);

      final found = await repository.findById(order.id);

      expect(found, isNotNull);
      expect(found!.id.value, order.id.value);
      expect(found.customerId, order.customerId);
    });

    test('findById returns null for an unknown order', () async {
      final repository = FirestoreCanonicalOrderRepository(
        client: _FakeOrderFirestoreClient(),
        resolveOrganizationId: (restaurantId) async => 'org-1',
      );

      expect(await repository.findById(OrderId('missing')), isNull);
    });

    test('findByCustomerId returns only that customer\'s orders', () async {
      final client = _FakeOrderFirestoreClient();
      final repository = FirestoreCanonicalOrderRepository(
        client: client,
        resolveOrganizationId: (restaurantId) async => 'org-1',
      );
      final orderA = await _buildOrder(customerId: 'uid-1', idPrefix: 'a');
      final orderB = await _buildOrder(customerId: 'uid-2', idPrefix: 'b');
      await repository.submitOrder(orderA);
      await repository.submitOrder(orderB);

      final found = await repository.findByCustomerId('uid-1');

      expect(found.map((o) => o.id.value), [orderA.id.value]);
    });

    test('findAll returns every submitted order regardless of customer',
        () async {
      final client = _FakeOrderFirestoreClient();
      final repository = FirestoreCanonicalOrderRepository(
        client: client,
        resolveOrganizationId: (restaurantId) async => 'org-1',
      );
      await repository
          .submitOrder(await _buildOrder(customerId: 'uid-1', idPrefix: 'a'));
      await repository
          .submitOrder(await _buildOrder(customerId: null, idPrefix: 'b'));

      expect(await repository.findAll(), hasLength(2));
    });
  });
}
