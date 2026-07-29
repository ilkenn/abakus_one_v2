import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/kitchen_display_session_repository.dart';
import '../../domain/kds/kitchen_display_session.dart';
import '../identity/kitchen_display_session_id_generator.dart';

/// Starts a new [KitchenDisplaySession] for a device — "session start"
/// (Phase 4G). Only one active session per device is ever permitted:
/// throws [KitchenDisplaySessionAlreadyActiveViolation] otherwise,
/// mirroring `OpenCashDrawer`'s equivalent guard.
class StartKitchenDisplaySession {
  const StartKitchenDisplaySession({
    required Clock clock,
    required KitchenDisplaySessionIdGenerator idGenerator,
    required KitchenDisplaySessionRepository repository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _repository = repository;

  final Clock _clock;
  final KitchenDisplaySessionIdGenerator _idGenerator;
  final KitchenDisplaySessionRepository _repository;

  Future<KitchenDisplaySession> call({
    required String deviceId,
    required String branchId,
  }) async {
    final existingActive = await _repository.findActiveByDeviceId(deviceId);
    if (existingActive != null) {
      throw KitchenDisplaySessionAlreadyActiveViolation(deviceId: deviceId);
    }

    final now = _clock.now();
    final session = KitchenDisplaySession(
      id: _idGenerator.nextSessionId(),
      deviceId: deviceId,
      branchId: branchId,
      status: KitchenDisplaySessionStatus.active,
      startedAt: now,
      lastHeartbeatAt: now,
      revision: 1,
    );
    await _repository.save(session);
    return session;
  }
}
