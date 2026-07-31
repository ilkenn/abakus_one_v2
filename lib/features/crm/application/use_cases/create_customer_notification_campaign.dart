import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/customer_notification_campaign_repository.dart';
import '../../domain/notifications/customer_notification_campaign.dart';
import '../../domain/segmentation/customer_category.dart';
import '../identity/customer_notification_campaign_id_generator.dart';

/// An administrator drafts a new [CustomerNotificationCampaign] —
/// manager-only ([PosAuthorizedAction.manageCustomerNotificationCampaigns]).
/// Always created in
/// [CustomerNotificationCampaignStatus.draft] — never a real send, per
/// this feature's own "architecture only" scope.
class CreateCustomerNotificationCampaign {
  const CreateCustomerNotificationCampaign({
    required PosAuthorizationPolicy authorizationPolicy,
    required CustomerNotificationCampaignIdGenerator idGenerator,
    required CustomerNotificationCampaignRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final CustomerNotificationCampaignIdGenerator _idGenerator;
  final CustomerNotificationCampaignRepository _repository;

  Future<CustomerNotificationCampaign> call({
    required String title,
    required String body,
    CustomerCategory? targetCategory,
    List<String> targetCustomerIds = const [],
    String? linkedCampaignId,
    required String performedByStaffId,
    required DateTime createdAt,
  }) async {
    const action = PosAuthorizedAction.manageCustomerNotificationCampaigns;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final campaign = CustomerNotificationCampaign(
      id: _idGenerator.nextCampaignId(),
      title: title,
      body: body,
      targetCategory: targetCategory,
      targetCustomerIds: targetCustomerIds,
      linkedCampaignId: linkedCampaignId,
      createdByStaffId: performedByStaffId,
      createdAt: createdAt,
      revision: 1,
    );
    await _repository.save(campaign);
    return campaign;
  }
}
