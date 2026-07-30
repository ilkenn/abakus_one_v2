import '../domain/location/courier_location_availability.dart';

/// Append-only storage for [CourierLocationAvailability] — no update or
/// delete method exists; every report is a new revision.
abstract interface class CourierLocationAvailabilityRepository {
  Future<void> save(CourierLocationAvailability availability);
  Future<CourierLocationAvailability?> findLatestByCourierId(String courierId);

  /// Full revision history, oldest first — Sprint 5B Part 8's
  /// `DetectRepeatedLocationLossSignal` needs this to count how often a
  /// courier's location becomes unavailable within a window; every other
  /// caller still only needs [findLatestByCourierId].
  Future<List<CourierLocationAvailability>> findHistoryByCourierId(
      String courierId);
}

class InMemoryCourierLocationAvailabilityRepository
    implements CourierLocationAvailabilityRepository {
  final Map<String, List<CourierLocationAvailability>> _byCourierId = {};

  @override
  Future<void> save(CourierLocationAvailability availability) async {
    _byCourierId
        .putIfAbsent(availability.courierId, () => [])
        .add(availability);
  }

  @override
  Future<CourierLocationAvailability?> findLatestByCourierId(
      String courierId) async {
    final history = _byCourierId[courierId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<List<CourierLocationAvailability>> findHistoryByCourierId(
      String courierId) async {
    return List.unmodifiable(_byCourierId[courierId] ?? const []);
  }
}
