import '../domain/models/order.dart';
import '../domain/models/order_id.dart';
import 'order_firestore_client.dart';
import 'order_firestore_mapper.dart';

/// The shared persistence boundary for the canonical [Order] aggregate —
/// Sprint 9D (`docs/decisions.md` ADR-026). Lives in `features/orders`
/// (the neutral home both `features/pos` and customer-facing checkout
/// already reference) rather than in either feature — unlike
/// `PosOrderRepository` (POS-only, draft-session-scoped),
/// [CanonicalOrderRepository] has no notion of a staff draft session; it
/// only ever stores/reads already-built, already-transitioned [Order]s,
/// exactly like `PosOrderRepository.submitOrder`/`findById` already do.
///
/// `InMemoryPosOrderRepository` (`features/pos/data/pos_order_repository.dart`)
/// delegates its own `submitOrder`/`findById` to an instance of this
/// interface — so an order submitted via POS and an order submitted via
/// customer checkout (`SubmitCustomerOrder`) land in the **same** store
/// when both are wired to the same provider instance
/// (`canonicalOrderRepositoryProvider`), satisfying "customer/POS/QR-
/// created orders all enter the same lifecycle" at the storage level, not
/// just the model-shape level.
abstract interface class CanonicalOrderRepository {
  /// Persists an already-built, already-transitioned [order] and returns
  /// it back — mirrors `PosOrderRepository.submitOrder`'s exact contract.
  Future<Order> submitOrder(Order order);

  Future<Order?> findById(OrderId orderId);

  /// Every order placed by [customerId] — the customer-facing order-
  /// history/tracking read path. Empty for a guest checkout (`Order
  /// .customerId == null` is never queryable this way, matching
  /// `Order.customerId`'s own "null for guest/anonymous" contract).
  Future<List<Order>> findByCustomerId(String customerId);

  /// Every order ever submitted, regardless of channel or customer —
  /// mirrors `InMemoryPosOrderRepository.submittedOrders`'s diagnostic
  /// role, promoted to a real interface method since this repository is
  /// shared across features rather than being one feature's own test
  /// convenience getter.
  Future<List<Order>> findAll();
}

/// In-memory [CanonicalOrderRepository] — the only implementation this
/// sprint (Sprint 9E migrates this behind a real Firestore-backed one,
/// same interface, same callers).
class InMemoryCanonicalOrderRepository implements CanonicalOrderRepository {
  final Map<String, Order> _byId = {};

  @override
  Future<Order> submitOrder(Order order) async {
    _byId[order.id.value] = order;
    return order;
  }

  @override
  Future<Order?> findById(OrderId orderId) async => _byId[orderId.value];

  @override
  Future<List<Order>> findByCustomerId(String customerId) async {
    return List.unmodifiable(
      _byId.values.where((order) => order.customerId == customerId),
    );
  }

  @override
  Future<List<Order>> findAll() async => List.unmodifiable(_byId.values);
}

/// The real, Firestore-backed [CanonicalOrderRepository] — Sprint 9E
/// (`docs/decisions.md` ADR-026). Every write resolves and denormalizes
/// `organizationId` via [resolveOrganizationId] (the caller-injected
/// restaurant→organization chain — mirrors
/// `RealPosAuthorizationPolicy.resolveRestaurantOrganizationId`'s exact
/// closure-injection pattern from Sprint 9B, keeping this `data/`-layer
/// class free of any `features/admin` dependency) — **fails closed**: an
/// order whose restaurant can't be resolved to a real organization is
/// never persisted, matching "tenant scope is resolved, never trusted."
class FirestoreCanonicalOrderRepository implements CanonicalOrderRepository {
  FirestoreCanonicalOrderRepository({
    required OrderFirestoreClient client,
    required Future<String?> Function(String restaurantId)
        resolveOrganizationId,
  })  : _client = client,
        _resolveOrganizationId = resolveOrganizationId;

  final OrderFirestoreClient _client;
  final Future<String?> Function(String restaurantId) _resolveOrganizationId;

  @override
  Future<Order> submitOrder(Order order) async {
    final organizationId = await _resolveOrganizationId(order.restaurantId);
    if (organizationId == null) {
      throw StateError(
        'Cannot resolve an organization for restaurant '
        '"${order.restaurantId}" — refusing to persist an order with no '
        'resolved tenant boundary.',
      );
    }
    await _client.setOrder(
      order.id.value,
      OrderFirestoreMapper.toFirestore(order, organizationId: organizationId),
    );
    return order;
  }

  @override
  Future<Order?> findById(OrderId orderId) async {
    final data = await _client.getOrder(orderId.value);
    return data == null ? null : OrderFirestoreMapper.fromFirestore(data);
  }

  @override
  Future<List<Order>> findByCustomerId(String customerId) async {
    final docs = await _client.queryOrdersByCustomerId(customerId);
    return [for (final doc in docs) OrderFirestoreMapper.fromFirestore(doc)];
  }

  @override
  Future<List<Order>> findAll() async {
    final docs = await _client.getAllOrders();
    return [for (final doc in docs) OrderFirestoreMapper.fromFirestore(doc)];
  }
}
