import '../data/device_token_repository.dart';

/// Revokes every active device token for [uid] — Sprint 9H
/// (`docs/decisions.md` ADR-026). The real consumer this sprint wires it
/// to is sign-out (`AuthNotifier.logout`) and account deletion
/// completion: neither should keep sending push notifications to a
/// device that is no longer meaningfully "signed in" as that user.
/// Idempotent — revoking an already-revoked token is a no-op, not an
/// error.
class RevokeDeviceTokensForUser {
  const RevokeDeviceTokensForUser({required DeviceTokenRepository repository})
      : _repository = repository;

  final DeviceTokenRepository _repository;

  Future<void> call({required String uid, required DateTime now}) async {
    final active = await _repository.findActiveByUid(uid);
    for (final token in active) {
      await _repository.save(token.copyWith(revokedAt: now));
    }
  }
}
