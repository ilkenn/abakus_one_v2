import '../../data/integration_audit_entry_repository.dart';
import '../../data/webhook_delivery_record_repository.dart';
import '../../domain/audit/integration_audit_entry.dart';
import '../../domain/audit/integration_audit_event_type.dart';
import '../../domain/webhook_delivery_record.dart';
import '../../domain/webhook_signature_verifier.dart';
import '../identity/webhook_delivery_record_id_generator.dart';

/// Records that a webhook delivery arrived — Phase 8
/// (`docs/decisions.md` ADR-025).
///
/// **A trusted internal primitive, not a screen-facing entry point** —
/// deliberately has no `PosAuthorizationPolicy` dependency, mirroring
/// `RecordMarketplaceOrderMapping`/`RecordPaymentSettlement`'s (8I/8J)
/// established precedent. The real caller would be a future backend's
/// HTTP handler, not a human actor — genuinely unreachable from this
/// client-only codebase, an even more fundamental gap than those two
/// (see `WebhookDeliveryRecord`'s own doc comment: no backend exists at
/// all to receive a real webhook).
///
/// **Idempotent by [externalDeliveryId]**: a provider redelivering the
/// same event (a normal, expected webhook behavior — "at least once"
/// delivery is the standard guarantee) returns the existing record
/// unchanged rather than processing it twice.
///
/// Never marks [WebhookSignatureVerifier]'s result as anything other
/// than what it actually reports — with [UnverifiedWebhookSignatureVerifier]
/// as the only implementation in this codebase, every recorded delivery
/// has `signatureVerified: false` today, honestly.
class RecordWebhookDelivery {
  const RecordWebhookDelivery({
    required WebhookSignatureVerifier signatureVerifier,
    required WebhookDeliveryRecordIdGenerator idGenerator,
    required WebhookDeliveryRecordRepository repository,
    required IntegrationAuditEntryRepository auditRepository,
  })  : _signatureVerifier = signatureVerifier,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final WebhookSignatureVerifier _signatureVerifier;
  final WebhookDeliveryRecordIdGenerator _idGenerator;
  final WebhookDeliveryRecordRepository _repository;
  final IntegrationAuditEntryRepository _auditRepository;

  Future<WebhookDeliveryRecord> call({
    required String organizationId,
    required String providerId,
    required String externalDeliveryId,
    required String eventType,
    required String rawPayload,
    required String signature,
    required String signingSecret,
    required DateTime receivedAt,
  }) async {
    final existing =
        await _repository.findByExternalDeliveryId(externalDeliveryId);
    if (existing != null) return existing;

    final verified = _signatureVerifier.verify(
      payload: rawPayload,
      signature: signature,
      secret: signingSecret,
    );

    final record = WebhookDeliveryRecord(
      id: _idGenerator.nextWebhookDeliveryRecordId(),
      organizationId: organizationId,
      providerId: providerId,
      externalDeliveryId: externalDeliveryId,
      eventType: eventType,
      rawPayload: rawPayload,
      signatureVerified: verified,
      receivedAt: receivedAt,
      revision: 1,
    );
    await _repository.save(record);

    await _auditRepository.appendEvent(IntegrationAuditEntry(
      id: '${record.id}-audit-received',
      organizationId: organizationId,
      actorId: 'system',
      type: IntegrationAuditEventType.webhookDeliveryReceived,
      description:
          'Webhook delivery "$externalDeliveryId" ($eventType) received '
          'from provider "$providerId" (signatureVerified: $verified)',
      targetEntityId: record.id,
      timestamp: receivedAt,
    ));

    return record;
  }
}
