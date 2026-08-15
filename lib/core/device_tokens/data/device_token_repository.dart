import 'package:cloud_firestore/cloud_firestore.dart' as fs;

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

/// Selected in release builds — closed during this phase's mandatory
/// adversarial security review, the same "no release build may silently
/// fall back to InMemory persistence" fix applied to
/// `AccountDeletionRequestRepository`. Lower real-world severity here
/// (a failed device-token registration only means no push notifications
/// for that device, not a security gap), but the same structural rule
/// applies uniformly rather than being judged case by case.
class ProductionUnavailableDeviceTokenRepository
    implements DeviceTokenRepository {
  const ProductionUnavailableDeviceTokenRepository();

  @override
  Future<void> save(DeviceToken deviceToken) async {
    throw StateError(
      'DeviceTokenRepository is unavailable in release builds — no real '
      'backend exists yet.',
    );
  }

  @override
  Future<List<DeviceToken>> findActiveByUid(String uid) async => const [];

  @override
  Future<DeviceToken?> findByToken(String token) async => null;
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

/// Faz R.3C — the real, production-backing implementation. `deviceTokens`
/// is already owner-scoped in `firestore.rules` (own-uid read/write,
/// `organizationIdUnchanged()` on update) — no rules change was needed for
/// this repository. Every record is a full document at
/// `deviceTokens/{deviceToken.id}`, `deviceToken.id` generated client-side
/// by [DeviceTokenIdGenerator] (mirrors [InMemoryDeviceTokenRepository]'s
/// own id scheme) rather than a Firestore auto-id, so [save] is always a
/// deterministic `.set()`, never a query-then-write.
class FirestoreDeviceTokenRepository implements DeviceTokenRepository {
  FirestoreDeviceTokenRepository({fs.FirebaseFirestore? firestore})
      : _firestore = firestore ?? fs.FirebaseFirestore.instance;

  final fs.FirebaseFirestore _firestore;

  fs.CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('deviceTokens');

  @override
  Future<void> save(DeviceToken deviceToken) async {
    await _collection.doc(deviceToken.id).set({
      'uid': deviceToken.uid,
      'organizationId': deviceToken.organizationId,
      'token': deviceToken.token,
      'platform': deviceToken.platform,
      'registeredAt': fs.Timestamp.fromDate(deviceToken.registeredAt),
      'revokedAt': deviceToken.revokedAt == null
          ? null
          : fs.Timestamp.fromDate(deviceToken.revokedAt!),
    });
  }

  @override
  Future<List<DeviceToken>> findActiveByUid(String uid) async {
    final snapshot = await _collection
        .where('uid', isEqualTo: uid)
        .where('revokedAt', isNull: true)
        .get();
    return snapshot.docs.map((d) => _map(d.id, d.data())).toList();
  }

  @override
  Future<DeviceToken?> findByToken(String token) async {
    final snapshot =
        await _collection.where('token', isEqualTo: token).limit(1).get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return _map(doc.id, doc.data());
  }

  DeviceToken _map(String id, Map<String, dynamic> data) {
    final revokedAt = data['revokedAt'] as fs.Timestamp?;
    return DeviceToken(
      id: id,
      uid: data['uid'] as String,
      organizationId: data['organizationId'] as String,
      token: data['token'] as String,
      platform: data['platform'] as String,
      registeredAt: (data['registeredAt'] as fs.Timestamp).toDate(),
      revokedAt: revokedAt?.toDate(),
    );
  }
}
