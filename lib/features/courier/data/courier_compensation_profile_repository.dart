import '../domain/compensation/courier_compensation_profile.dart';

/// Append-only storage for [CourierCompensationProfile] — no update or
/// delete method exists; a rate change is always a brand-new, higher-
/// [CourierCompensationProfile.version] record.
abstract interface class CourierCompensationProfileRepository {
  Future<void> append(CourierCompensationProfile profile);
  Future<CourierCompensationProfile?> findById(String id);

  /// Every version ever created for [courierId], oldest first.
  Future<List<CourierCompensationProfile>> findAllByCourierId(String courierId);

  /// The single profile version that [CourierCompensationProfile.coversAt]
  /// [at], or `null` if none has been configured yet for [courierId] at
  /// that instant.
  Future<CourierCompensationProfile?> findEffectiveAt({
    required String courierId,
    required DateTime at,
  });
}

class InMemoryCourierCompensationProfileRepository
    implements CourierCompensationProfileRepository {
  final Map<String, List<CourierCompensationProfile>> _byCourierId = {};
  final Map<String, CourierCompensationProfile> _byId = {};

  @override
  Future<void> append(CourierCompensationProfile profile) async {
    _byCourierId.putIfAbsent(profile.courierId, () => []).add(profile);
    _byId[profile.id] = profile;
  }

  @override
  Future<CourierCompensationProfile?> findById(String id) async => _byId[id];

  @override
  Future<List<CourierCompensationProfile>> findAllByCourierId(
      String courierId) async {
    return List.unmodifiable(_byCourierId[courierId] ?? const []);
  }

  @override
  Future<CourierCompensationProfile?> findEffectiveAt({
    required String courierId,
    required DateTime at,
  }) async {
    final versions = _byCourierId[courierId] ?? const [];
    CourierCompensationProfile? best;
    for (final profile in versions) {
      if (!profile.coversAt(at)) continue;
      if (best == null || profile.version > best.version) best = profile;
    }
    return best;
  }
}
