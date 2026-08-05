import '../domain/device_token.dart';

/// Storage for [DeviceToken] — mirrors every other repository interface's
/// shape in this codebase.
abstract interface class DeviceTokenRepository {
  Future<void> save(DeviceToken deviceToken);

  /// Every currently-active (not revoked) token for [uid] — what a
  /// future real push-sending path would fan out to.
  Future<List<DeviceToken>> findActiveByUid(String uid);

  /// `null` if no token was ever registered with this exact [token]
  /// value — used to make registration idempotent (the same physical
  /// device registering twice must not create two records).
  Future<DeviceToken?> findByToken(String token);
}

/// In-memory implementation — the only one this sprint (mirrors Sprint
/// 9E/9G's "one pilot slice per sprint" discipline; a real Firestore-
/// backed implementation is future controlled migration work).
class InMemoryDeviceTokenRepository implements DeviceTokenRepository {
  final Map<String, DeviceToken> _byId = {};

  @override
  Future<void> save(DeviceToken deviceToken) async {
    _byId[deviceToken.id] = deviceToken;
  }

  @override
  Future<List<DeviceToken>> findActiveByUid(String uid) async {
    return List.unmodifiable(
      _byId.values.where((t) => t.uid == uid && t.isActive),
    );
  }

  @override
  Future<DeviceToken?> findByToken(String token) async {
    for (final deviceToken in _byId.values) {
      if (deviceToken.token == token) return deviceToken;
    }
    return null;
  }
}
