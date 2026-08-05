import '../domain/models/order.dart';
import '../domain/models/order_id.dart';

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
