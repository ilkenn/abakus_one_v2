import '../domain/delivery/delivery_route_snapshot.dart';

/// Storage for [DeliveryRouteSnapshot] estimates — the "DeliveryTrackingRepository"
/// named in the Phase 5 brief. Append-only; a new estimate is a new
/// snapshot, never an edit.
abstract interface class DeliveryTrackingRepository {
  Future<void> append(DeliveryRouteSnapshot snapshot);
  Future<DeliveryRouteSnapshot?> findLatestByDeliveryId(String deliveryId);
}

class InMemoryDeliveryTrackingRepository implements DeliveryTrackingRepository {
  final Map<String, List<DeliveryRouteSnapshot>> _byDeliveryId = {};

  @override
  Future<void> append(DeliveryRouteSnapshot snapshot) async {
    _byDeliveryId.putIfAbsent(snapshot.deliveryId, () => []).add(snapshot);
  }

  @override
  Future<DeliveryRouteSnapshot?> findLatestByDeliveryId(
      String deliveryId) async {
    final history = _byDeliveryId[deliveryId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }
}
