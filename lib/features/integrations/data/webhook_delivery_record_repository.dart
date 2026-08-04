import '../domain/webhook_delivery_record.dart';

abstract interface class WebhookDeliveryRecordRepository {
  Future<void> save(WebhookDeliveryRecord record);
  Future<WebhookDeliveryRecord?> findByExternalDeliveryId(
      String externalDeliveryId);
  Future<List<WebhookDeliveryRecord>> findByOrganizationId(
      String organizationId);
}

class InMemoryWebhookDeliveryRecordRepository
    implements WebhookDeliveryRecordRepository {
  final Map<String, WebhookDeliveryRecord> _byExternalDeliveryId = {};

  @override
  Future<void> save(WebhookDeliveryRecord record) async =>
      _byExternalDeliveryId[record.externalDeliveryId] = record;

  @override
  Future<WebhookDeliveryRecord?> findByExternalDeliveryId(
      String externalDeliveryId) async {
    return _byExternalDeliveryId[externalDeliveryId];
  }

  @override
  Future<List<WebhookDeliveryRecord>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _byExternalDeliveryId.values
          .where((r) => r.organizationId == organizationId),
    );
  }
}
