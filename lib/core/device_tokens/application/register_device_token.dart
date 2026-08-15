import '../data/device_token_repository.dart';
import '../domain/device_token.dart';
import 'device_token_id_generator.dart';

/// Registers (or idempotently returns an already-registered) FCM device
/// token — Sprint 9H (`docs/decisions.md` ADR-026). A device that
/// re-registers the same physical token (e.g. app restart) finds the
/// existing record via [DeviceTokenRepository.findByToken] rather than
/// creating a duplicate; if it had been revoked, re-registering
/// reactivates it under a fresh id instead of silently un-revoking the
/// old record (mirrors this codebase's append-first-then-mark
/// convention — a revoked record's history is never rewritten).
///
/// **Faz R.3C fix**: the previous version returned any active [existing]
/// record unconditionally, without checking it actually belonged to the
/// calling [uid]. On a shared/reused device, customer B signing in and
/// re-registering the exact same physical FCM token that customer A's
/// session had registered would silently keep the token "active" under
/// A — B's pushes would go nowhere, and worse, A would keep receiving
/// pushes meant for B's reservations. Now: a token found active under a
/// *different* uid is revoked first, then a fresh record is created for
/// the calling [uid] — the same "never rewrite a revoked record, append a
/// new one instead" convention already used for reactivation.
class RegisterDeviceToken {
  const RegisterDeviceToken({
    required DeviceTokenRepository repository,
    required DeviceTokenIdGenerator idGenerator,
  })  : _repository = repository,
        _idGenerator = idGenerator;

  final DeviceTokenRepository _repository;
  final DeviceTokenIdGenerator _idGenerator;

  Future<DeviceToken> call({
    required String uid,
    required String organizationId,
    required String token,
    required String platform,
    required DateTime now,
  }) async {
    final existing = await _repository.findByToken(token);
    if (existing != null && existing.isActive) {
      if (existing.uid == uid) return existing;
      await _repository.save(existing.copyWith(revokedAt: now));
    }

    final deviceToken = DeviceToken(
      id: _idGenerator.nextTokenId(),
      uid: uid,
      organizationId: organizationId,
      token: token,
      platform: platform,
      registeredAt: now,
    );
    await _repository.save(deviceToken);
    return deviceToken;
  }
}
