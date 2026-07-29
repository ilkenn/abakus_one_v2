import '../domain/identity/courier_operational_profile.dart';

/// Storage for [CourierOperationalProfile] — one current record per
/// courier, mutable (mirrors the registry-entity pattern, not append-only:
/// document/compensation metadata is corrected in place, not versioned).
abstract interface class CourierOperationalProfileRepository {
  Future<void> save(CourierOperationalProfile profile);
  Future<CourierOperationalProfile?> findByCourierId(String courierId);
}

class InMemoryCourierOperationalProfileRepository
    implements CourierOperationalProfileRepository {
  final Map<String, CourierOperationalProfile> _byCourierId = {};

  @override
  Future<void> save(CourierOperationalProfile profile) async =>
      _byCourierId[profile.courierId] = profile;

  @override
  Future<CourierOperationalProfile?> findByCourierId(String courierId) async =>
      _byCourierId[courierId];
}
