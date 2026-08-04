import 'package:abakus_one_v2/features/integrations/application/identity/webhook_delivery_record_id_generator.dart';
import 'package:abakus_one_v2/features/integrations/application/use_cases/record_webhook_delivery.dart';
import 'package:abakus_one_v2/features/integrations/data/integration_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/integrations/data/webhook_delivery_record_repository.dart';
import 'package:abakus_one_v2/features/integrations/domain/audit/integration_audit_event_type.dart';
import 'package:abakus_one_v2/features/integrations/domain/webhook_delivery_status.dart';
import 'package:abakus_one_v2/features/integrations/domain/webhook_signature_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecordWebhookDelivery', () {
    test('records a delivery, unverified by default', () async {
      final repository = InMemoryWebhookDeliveryRecordRepository();
      final auditRepository = InMemoryIntegrationAuditEntryRepository();
      final useCase = RecordWebhookDelivery(
        signatureVerifier: const UnverifiedWebhookSignatureVerifier(),
        idGenerator: SequentialWebhookDeliveryRecordIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final record = await useCase(
        organizationId: 'org-1',
        providerId: 'yemeksepeti',
        externalDeliveryId: 'ext-delivery-1',
        eventType: 'order.created',
        rawPayload: '{"orderId":"123"}',
        signature: 'sig-1',
        signingSecret: 'secret-1',
        receivedAt: DateTime(2026, 1, 1),
      );

      expect(record.signatureVerified, isFalse);
      expect(record.status, WebhookDeliveryStatus.received);

      final entries = await auditRepository.findByTargetEntityId(record.id);
      expect(
        entries.single.type,
        IntegrationAuditEventType.webhookDeliveryReceived,
      );
    });

    test('is idempotent by externalDeliveryId — a redelivery is a no-op',
        () async {
      final repository = InMemoryWebhookDeliveryRecordRepository();
      final auditRepository = InMemoryIntegrationAuditEntryRepository();
      final useCase = RecordWebhookDelivery(
        signatureVerifier: const UnverifiedWebhookSignatureVerifier(),
        idGenerator: SequentialWebhookDeliveryRecordIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final first = await useCase(
        organizationId: 'org-1',
        providerId: 'yemeksepeti',
        externalDeliveryId: 'ext-delivery-1',
        eventType: 'order.created',
        rawPayload: '{"orderId":"123"}',
        signature: 'sig-1',
        signingSecret: 'secret-1',
        receivedAt: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        organizationId: 'org-1',
        providerId: 'yemeksepeti',
        externalDeliveryId: 'ext-delivery-1',
        eventType: 'order.created',
        rawPayload: '{"orderId":"123"}',
        signature: 'sig-1',
        signingSecret: 'secret-1',
        receivedAt: DateTime(2026, 1, 2),
      );

      expect(second.id, first.id);
      final entries = await auditRepository.findByTargetEntityId(first.id);
      expect(entries, hasLength(1));
    });
  });
}
