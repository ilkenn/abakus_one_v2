import '../domain/availability/courier_package_blocking_status.dart';

/// Append-only storage for [CourierPackageBlockingStatus] — Sprint 5C.
abstract interface class CourierPackageBlockingStatusRepository {
  Future<void> save(CourierPackageBlockingStatus status);
  Future<CourierPackageBlockingStatus?> findByCourierId(String courierId);
}

class InMemoryCourierPackageBlockingStatusRepository
    implements CourierPackageBlockingStatusRepository {
  final Map<String, List<CourierPackageBlockingStatus>> _byCourierId = {};

  @override
  Future<void> save(CourierPackageBlockingStatus status) async {
    _byCourierId.putIfAbsent(status.courierId, () => []).add(status);
  }

  @override
  Future<CourierPackageBlockingStatus?> findByCourierId(
      String courierId) async {
    final history = _byCourierId[courierId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }
}
