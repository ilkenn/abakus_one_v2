abstract interface class CustomerNotificationCampaignIdGenerator {
  String nextCampaignId();
}

class SequentialCustomerNotificationCampaignIdGenerator
    implements CustomerNotificationCampaignIdGenerator {
  SequentialCustomerNotificationCampaignIdGenerator({
    this.prefix = 'notif-campaign',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextCampaignId() => '$prefix-${++_sequence}';
}
