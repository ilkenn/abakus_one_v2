import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../data/courier_cash_collection_repository.dart';
import '../../data/courier_cash_declaration_repository.dart';
import '../../data/courier_settlement_audit_entry_repository.dart';
import '../../data/courier_settlement_session_repository.dart';
import '../../domain/courier_settlement/courier_cash_declaration.dart';
import '../../domain/courier_settlement/courier_settlement_audit_entry.dart';
import '../../domain/courier_settlement/courier_settlement_audit_event_type.dart';
import '../../domain/courier_settlement/courier_settlement_session_status.dart';
import '../../domain/courier_settlement/courier_settlement_variance.dart';
import '../identity/courier_cash_declaration_id_generator.dart';

/// Submits a new [CourierCashDeclaration] for a [CourierSettlementSession]
/// — "Collect Cash -> Declare Cash" (Phase 3 Sprint 3F). [expectedAmount]
/// is computed here, once, as the sum of every `CourierCashCollection`
/// recorded for the session so far — frozen onto the resulting
/// [CourierCashDeclaration] so a later collection can never retroactively
/// change what an already-submitted declaration's expected figure was.
/// Mirrors `SubmitCashCount` exactly.
///
/// Transitions the session to `pendingApproval` from either `active` or
/// `rejected` (`CourierSettlementSessionStatusTransitions`) — a rejected
/// session needs no separate "reactivate" step before a redeclaration.
/// **Never overwrites a previous declaration** — every call appends a
/// brand-new [CourierCashDeclaration].
class SubmitCourierCashDeclaration {
  const SubmitCourierCashDeclaration({
    required Clock clock,
    required CourierCashDeclarationIdGenerator idGenerator,
    required CourierSettlementSessionRepository sessionRepository,
    required CourierCashCollectionRepository collectionRepository,
    required CourierCashDeclarationRepository declarationRepository,
    required CourierSettlementAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _sessionRepository = sessionRepository,
        _collectionRepository = collectionRepository,
        _declarationRepository = declarationRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CourierCashDeclarationIdGenerator _idGenerator;
  final CourierSettlementSessionRepository _sessionRepository;
  final CourierCashCollectionRepository _collectionRepository;
  final CourierCashDeclarationRepository _declarationRepository;
  final CourierSettlementAuditEntryRepository _auditRepository;

  Future<CourierCashDeclaration> call({
    required String settlementSessionId,
    required Money declaredAmount,
    String notes = '',
  }) async {
    final session = await _sessionRepository.findById(settlementSessionId);
    if (session == null) {
      throw UnknownCourierSettlementEntityViolation(
        entityName: 'CourierSettlementSession',
        id: settlementSessionId,
      );
    }
    if (session.status != CourierSettlementSessionStatus.active &&
        session.status != CourierSettlementSessionStatus.rejected) {
      throw CourierSettlementSessionNotActiveViolation(
        sessionId: settlementSessionId,
        statusName: session.status.name,
      );
    }

    final collections = await _collectionRepository
        .findBySettlementSessionId(settlementSessionId);
    final expectedAmount = collections.fold<Money>(
      Money.zero(Currency.accountingCurrency),
      (sum, collection) => sum + collection.collectedAmount,
    );

    final now = _clock.now();
    final declaration = CourierCashDeclaration(
      id: _idGenerator.nextDeclarationId(),
      settlementSessionId: settlementSessionId,
      courierId: session.courierId,
      expectedAmount: expectedAmount,
      declaredAmount: declaredAmount,
      variance: CourierSettlementVariance.compute(
        expectedAmount: expectedAmount,
        declaredAmount: declaredAmount,
      ),
      declaredAt: now,
      notes: notes,
    );
    await _declarationRepository.append(declaration);

    await _sessionRepository.save(session.copyWith(
      status: CourierSettlementSessionStatus.pendingApproval,
      revision: session.revision + 1,
    ));

    await _auditRepository.appendEvent(CourierSettlementAuditEntry(
      id: '${declaration.id}-audit',
      courierId: session.courierId,
      settlementSessionId: settlementSessionId,
      type: CourierSettlementAuditEventType.declarationSubmitted,
      description:
          'Cash declaration submitted: variance ${declaration.variance.type.name}',
      actorStaffId: session.courierId,
      timestamp: now,
      newValue: declaration.id,
    ));

    return declaration;
  }
}
