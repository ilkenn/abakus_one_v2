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
    required String token,
    required String platform,
    required DateTime now,
  }) async {
    final existing = await _repository.findByToken(token);
    if (existing != null && existing.isActive) return existing;

    final deviceToken = DeviceToken(
      id: _idGenerator.nextTokenId(),
      uid: uid,
      token: token,
      platform: platform,
      registeredAt: now,
    );
    await _repository.save(deviceToken);
    return deviceToken;
  }
}
