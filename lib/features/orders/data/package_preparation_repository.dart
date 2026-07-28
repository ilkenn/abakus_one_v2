import '../domain/fulfillment/package_preparation.dart';
import '../domain/models/order_id.dart';

/// Append-only storage for [PackagePreparation] revisions, keyed by
/// [OrderId] — mirrors `OrderClosureRepository`'s shape.
abstract interface class PackagePreparationRepository {
  Future<void> save(PackagePreparation preparation);

  /// The latest revision for [orderId], or `null` if none exists yet.
  Future<PackagePreparation?> findCurrentByOrderId(OrderId orderId);

  /// Every revision ever saved for [orderId], oldest first.
  Future<List<PackagePreparation>> findHistoryByOrderId(OrderId orderId);
}

/// In-memory [PackagePreparationRepository] — the only implementation
/// this sprint.
class InMemoryPackagePreparationRepository
    implements PackagePreparationRepository {
  final Map<String, List<PackagePreparation>> _historyByOrderId = {};

  @override
  Future<void> save(PackagePreparation preparation) async {
    _historyByOrderId
        .putIfAbsent(preparation.orderId.value, () => [])
        .add(preparation);
  }

  @override
  Future<PackagePreparation?> findCurrentByOrderId(OrderId orderId) async {
    final history = _historyByOrderId[orderId.value];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<List<PackagePreparation>> findHistoryByOrderId(OrderId orderId) async {
    return List.unmodifiable(_historyByOrderId[orderId.value] ?? const []);
  }
}
