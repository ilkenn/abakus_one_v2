abstract interface class WebhookDeliveryRecordIdGenerator {
  String nextWebhookDeliveryRecordId();
}

class SequentialWebhookDeliveryRecordIdGenerator
    implements WebhookDeliveryRecordIdGenerator {
  SequentialWebhookDeliveryRecordIdGenerator({this.prefix = 'webhook'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextWebhookDeliveryRecordId() => '$prefix-${++_sequence}';
}
