import '../../../../shared/models/money.dart';
import '../../data/payment_hub_audit_entry_repository.dart';
import '../../data/payment_settlement_record_repository.dart';
import '../../domain/audit/payment_hub_audit_entry.dart';
import '../../domain/audit/payment_hub_audit_event_type.dart';
import '../../domain/payment_settlement_record.dart';
import '../identity/payment_settlement_record_id_generator.dart';

/// Records that a payment provider reported a settlement/payout batch —
/// Phase 8 (`docs/decisions.md` ADR-025), "Merchant Account →
/// Settlement."
///
/// **A trusted internal primitive, not a screen-facing entry point** —
/// deliberately has no `PosAuthorizationPolicy` dependency, mirroring
/// `RecordMarketplaceOrderMapping`'s (8I) and `RecordStockMovement`'s
/// (Phase 7) established precedent: the real caller is a future webhook
/// handler (Webhook Foundation, 8L), genuinely unreachable from
/// production code this phase — "do NOT integrate providers yet."
///
/// **Idempotent by [externalSettlementId]**: a duplicate call for a
/// settlement already recorded returns the existing record unchanged.
class RecordPaymentSettlement {
  const RecordPaymentSettlement({
    required PaymentSettlementRecordIdGenerator idGenerator,
    required PaymentSettlementRecordRepository repository,
    required PaymentHubAuditEntryRepository auditRepository,
  })  : _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PaymentSettlementRecordIdGenerator _idGenerator;
  final PaymentSettlementRecordRepository _repository;
  final PaymentHubAuditEntryRepository _auditRepository;

  Future<PaymentSettlementRecord> call({
    required String organizationId,
    required String merchantAccountId,
    required String externalSettlementId,
    required Money amount,
    required DateTime settledAt,
  }) async {
    final existing =
        await _repository.findByExternalSettlementId(externalSettlementId);
    if (existing != null) return existing;

    final record = PaymentSettlementRecord(
      id: _idGenerator.nextPaymentSettlementRecordId(),
      merchantAccountId: merchantAccountId,
      externalSettlementId: externalSettlementId,
      amount: amount,
      settledAt: settledAt,
      revision: 1,
    );
    await _repository.save(record);

    await _auditRepository.appendEvent(PaymentHubAuditEntry(
      id: '${record.id}-audit-recorded',
      organizationId: organizationId,
      actorId: 'system',
      type: PaymentHubAuditEventType.settlementRecorded,
      description: 'Settlement "$externalSettlementId" recorded for '
          'merchant account "$merchantAccountId"',
      targetEntityId: record.id,
      timestamp: settledAt,
    ));

    return record;
  }
}
