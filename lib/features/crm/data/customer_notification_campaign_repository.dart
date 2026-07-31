import '../domain/notifications/customer_notification_campaign.dart';

/// Storage for [CustomerNotificationCampaign] — mutable registry entity,
/// mirrors `SurveyRepository`.
abstract interface class CustomerNotificationCampaignRepository {
  Future<void> save(CustomerNotificationCampaign campaign);
  Future<CustomerNotificationCampaign?> findById(String campaignId);
  Future<List<CustomerNotificationCampaign>> findAll();
}

class InMemoryCustomerNotificationCampaignRepository
    implements CustomerNotificationCampaignRepository {
  final Map<String, CustomerNotificationCampaign> _byId = {};

  @override
  Future<void> save(CustomerNotificationCampaign campaign) async =>
      _byId[campaign.id] = campaign;

  @override
  Future<CustomerNotificationCampaign?> findById(String campaignId) async =>
      _byId[campaignId];

  @override
  Future<List<CustomerNotificationCampaign>> findAll() async =>
      List.unmodifiable(_byId.values);
}
