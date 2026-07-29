import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../data/courier_cash_collection_repository.dart';
import '../../data/courier_settlement_audit_entry_repository.dart';
import '../../data/courier_settlement_session_repository.dart';
import '../../data/payment_session_repository.dart';
import '../../domain/courier_settlement/courier_cash_collection.dart';
import '../../domain/courier_settlement/courier_collection_type.dart';
import '../../domain/courier_settlement/courier_settlement_audit_entry.dart';
import '../../domain/courier_settlement/courier_settlement_audit_event_type.dart';
import '../../domain/courier_settlement/courier_settlement_session_status.dart';
import '../identity/courier_cash_collection_id_generator.dart';

/// Records one [CourierCashCollection] against an active
/// [CourierSettlementSession] — "Collect Cash" (Phase 3 Sprint 3F).
/// Covers cash collected from a customer, cash-on-delivery, and (via
/// [CourierCollectionType.partial]/[CourierCollectionType.failed]) partial
/// and failed collections alike — always the same shape of record,
/// differing only by [collectionType] and [collectedAmount].
///
/// [orderId] and [paymentSessionId] must both already exist —
/// [paymentSessionId] is validated against `PaymentSessionRepository`
/// (`docs/business_rules.md` BR-COURIER-010: every collection references
/// an existing `PaymentSession`, never a fabricated one), throwing
/// [UnknownCourierSettlementEntityViolation] otherwise. This use case
/// never reads or writes the `PaymentSession` itself — only confirms it
/// exists — so it can never duplicate or alter a financial event Sprint
/// 3C already recorded.
class RecordCourierCashCollection {
  const RecordCourierCashCollection({
    required Clock clock,
    required CourierCashCollectionIdGenerator idGenerator,
    required CourierSettlementSessionRepository sessionRepository,
    required PaymentSessionRepository paymentSessionRepository,
    required CourierCashCollectionRepository collectionRepository,
    required CourierSettlementAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _sessionRepository = sessionRepository,
        _paymentSessionRepository = paymentSessionRepository,
        _collectionRepository = collectionRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CourierCashCollectionIdGenerator _idGenerator;
  final CourierSettlementSessionRepository _sessionRepository;
  final PaymentSessionRepository _paymentSessionRepository;
  final CourierCashCollectionRepository _collectionRepository;
  final CourierSettlementAuditEntryRepository _auditRepository;

  Future<CourierCashCollection> call({
    required String settlementSessionId,
    required OrderId orderId,
    required String paymentSessionId,
    required Money collectedAmount,
    required CourierCollectionType collectionType,
    String notes = '',
  }) async {
    final session = await _sessionRepository.findById(settlementSessionId);
    if (session == null) {
      throw UnknownCourierSettlementEntityViolation(
        entityName: 'CourierSettlementSession',
        id: settlementSessionId,
      );
    }
    if (session.status != CourierSettlementSessionStatus.active) {
      throw CourierSettlementSessionNotActiveViolation(
        sessionId: settlementSessionId,
        statusName: session.status.name,
      );
    }

    final paymentSession =
        await _paymentSessionRepository.findBySessionId(paymentSessionId);
    if (paymentSession == null) {
      throw UnknownCourierSettlementEntityViolation(
        entityName: 'PaymentSession',
        id: paymentSessionId,
      );
    }

    if (collectedAmount.isNegative) {
      throw NegativeAmountViolation(
        context: 'RecordCourierCashCollection.collectedAmount',
        minorUnits: collectedAmount.minorUnits,
        currencyCode: collectedAmount.currency.isoCode,
      );
    }

    final now = _clock.now();
    final collection = CourierCashCollection(
      id: _idGenerator.nextCollectionId(),
      settlementSessionId: settlementSessionId,
      courierId: session.courierId,
      orderId: orderId,
      paymentSessionId: paymentSessionId,
      collectedAmount: collectedAmount,
      collectionType: collectionType,
      collectedAt: now,
      notes: notes,
    );
    await _collectionRepository.append(collection);

    await _auditRepository.appendEvent(CourierSettlementAuditEntry(
      id: '${collection.id}-audit',
      courierId: session.courierId,
      settlementSessionId: settlementSessionId,
      type: CourierSettlementAuditEventType.collectionRecorded,
      description: '${collectionType.name} collection for order "$orderId": '
          '${collectedAmount.minorUnits} minor units',
      actorStaffId: session.courierId,
      timestamp: now,
      newValue: collection.id,
    ));

    return collection;
  }
}
