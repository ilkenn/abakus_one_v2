import '../domain/availability/courier_availability.dart';

/// Append-only storage for [CourierAvailability] revisions, keyed by
/// [CourierAvailability.courierId] — availability history stays fully
/// auditable, per the explicit rule.
abstract interface class CourierAvailabilityRepository {
  Future<void> save(CourierAvailability availability);
  Future<CourierAvailability?> findByCourierId(String courierId);
  Future<List<CourierAvailability>> findHistoryByCourierId(String courierId);
}

class InMemoryCourierAvailabilityRepository
    implements CourierAvailabilityRepository {
  final Map<String, List<CourierAvailability>> _historyByCourierId = {};

  @override
  Future<void> save(CourierAvailability availability) async {
    _historyByCourierId
        .putIfAbsent(availability.courierId, () => [])
        .add(availability);
  }

  @override
  Future<CourierAvailability?> findByCourierId(String courierId) async {
    final history = _historyByCourierId[courierId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<List<CourierAvailability>> findHistoryByCourierId(
      String courierId) async {
    return List.unmodifiable(_historyByCourierId[courierId] ?? const []);
  }
}
