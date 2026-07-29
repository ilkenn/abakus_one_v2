import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/kitchen_display_session_repository.dart';
import '../../domain/kds/kitchen_display_session.dart';

/// Ends an active [KitchenDisplaySession] — "session end" (Phase 4G).
class EndKitchenDisplaySession {
  const EndKitchenDisplaySession({
    required Clock clock,
    required KitchenDisplaySessionRepository repository,
  })  : _clock = clock,
        _repository = repository;

  final Clock _clock;
  final KitchenDisplaySessionRepository _repository;

  Future<KitchenDisplaySession> call({required String deviceId}) async {
    final session = await _repository.findActiveByDeviceId(deviceId);
    if (session == null) {
      throw UnknownKdsEntityViolation(
        entityName: 'KitchenDisplaySession',
        id: deviceId,
      );
    }

    final now = _clock.now();
    final ended = session.copyWith(
      status: KitchenDisplaySessionStatus.ended,
      endedAt: now,
      revision: session.revision + 1,
    );
    await _repository.save(ended);
    return ended;
  }
}
