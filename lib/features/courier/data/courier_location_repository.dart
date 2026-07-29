import '../domain/location/courier_location_snapshot.dart';

/// Append-only storage for [CourierLocationSnapshot] — the
/// "CourierLocationRepository" named in the Phase 5 brief.
abstract interface class CourierLocationRepository {
  Future<void> append(CourierLocationSnapshot snapshot);
  Future<CourierLocationSnapshot?> findLatestByCourierId(String courierId);
  Future<List<CourierLocationSnapshot>> findByDeliveryId(String deliveryId);
}

class InMemoryCourierLocationRepository implements CourierLocationRepository {
  final Map<String, List<CourierLocationSnapshot>> _byCourierId = {};
  final List<CourierLocationSnapshot> _all = [];

  @override
  Future<void> append(CourierLocationSnapshot snapshot) async {
    _byCourierId.putIfAbsent(snapshot.courierId, () => []).add(snapshot);
    _all.add(snapshot);
  }

  @override
  Future<CourierLocationSnapshot?> findLatestByCourierId(
      String courierId) async {
    final history = _byCourierId[courierId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<List<CourierLocationSnapshot>> findByDeliveryId(
      String deliveryId) async {
    return List.unmodifiable(
      _all.where((s) => s.deliveryId == deliveryId),
    );
  }
}
