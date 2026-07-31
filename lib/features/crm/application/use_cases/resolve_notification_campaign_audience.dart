import '../../data/customer_repository.dart';
import '../../domain/notifications/customer_notification_campaign.dart';
import '../../domain/segmentation/customer.dart';

/// Resolves exactly which [Customer]s a [CustomerNotificationCampaign]
/// would reach — **never sends anything**, stops precisely at "who would
/// receive this," per the brief's explicit "do NOT implement push
/// providers" instruction. Pure: no side effects beyond the repository
/// read it needs.
///
/// Targeting precedence: an explicit
/// [CustomerNotificationCampaign.targetCustomerIds] list (when non-empty)
/// wins over [CustomerNotificationCampaign.targetCategory] — "target
/// these specific customers" is a stronger instruction than "target this
/// segment." When neither is set, the audience is every customer
/// (a broadcast).
class ResolveNotificationCampaignAudience {
  const ResolveNotificationCampaignAudience({
    required CustomerRepository customerRepository,
  }) : _customerRepository = customerRepository;

  final CustomerRepository _customerRepository;

  Future<List<Customer>> call(CustomerNotificationCampaign campaign) async {
    if (campaign.targetCustomerIds.isNotEmpty) {
      final customers = <Customer>[];
      for (final customerId in campaign.targetCustomerIds) {
        final customer = await _customerRepository.findById(customerId);
        if (customer != null) customers.add(customer);
      }
      return customers;
    }

    final category = campaign.targetCategory;
    if (category != null) {
      return _customerRepository.findByCategory(category);
    }

    return _customerRepository.findAll();
  }
}
