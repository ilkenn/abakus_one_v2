import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_settlement_session_repository.dart';
import '../../domain/courier_settlement/courier_settlement_session.dart';
import '../../domain/courier_settlement/courier_settlement_session_status.dart';
import '../identity/courier_settlement_session_id_generator.dart';

/// Opens a new [CourierSettlementSession] for a courier — the start of
/// "Courier Shift -> Collect Cash" (Phase 3 Sprint 3F). Only one active
/// (non-`closed`) session may exist per courier at a time: throws
/// [CourierSettlementSessionAlreadyActiveViolation] if
/// `CourierSettlementSessionRepository.findActiveByCourierId` already
/// returns one — mirrors `OpenCashDrawer`'s equivalent check exactly.
class OpenCourierSettlementSession {
  const OpenCourierSettlementSession({
    required Clock clock,
    required CourierSettlementSessionIdGenerator idGenerator,
    required CourierSettlementSessionRepository sessionRepository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _sessionRepository = sessionRepository;

  final Clock _clock;
  final CourierSettlementSessionIdGenerator _idGenerator;
  final CourierSettlementSessionRepository _sessionRepository;

  Future<CourierSettlementSession> call({
    required String courierId,
    required String branchId,
  }) async {
    final existingActive =
        await _sessionRepository.findActiveByCourierId(courierId);
    if (existingActive != null) {
      throw CourierSettlementSessionAlreadyActiveViolation(
          courierId: courierId);
    }

    final session = CourierSettlementSession(
      id: _idGenerator.nextSettlementSessionId(),
      courierId: courierId,
      branchId: branchId,
      status: CourierSettlementSessionStatus.active,
      openedAt: _clock.now(),
      revision: 1,
    );
    await _sessionRepository.save(session);
    return session;
  }
}
