import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/customer_notification_campaign_repository.dart';
import '../../domain/notifications/customer_notification_campaign.dart';
import '../../domain/notifications/customer_notification_campaign_status.dart';

/// An administrator schedules a draft [CustomerNotificationCampaign] for
/// a future send — manager-only
/// ([PosAuthorizedAction.manageCustomerNotificationCampaigns]). Only a
/// [CustomerNotificationCampaignStatus.draft] campaign may be scheduled.
/// This moves [CustomerNotificationCampaign.status] to `scheduled` and
/// records [scheduledFor] — **it never sends anything**; no real push
/// provider exists to act on this schedule, per this feature's own
/// "architecture only" scope.
class ScheduleCustomerNotificationCampaign {
  const ScheduleCustomerNotificationCampaign({
    required PosAuthorizationPolicy authorizationPolicy,
    required CustomerNotificationCampaignRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final CustomerNotificationCampaignRepository _repository;

  Future<CustomerNotificationCampaign> call({
    required String campaignId,
    required DateTime scheduledFor,
    required String performedByStaffId,
  }) async {
    const action = PosAuthorizedAction.manageCustomerNotificationCampaigns;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(campaignId);
    if (existing == null) {
      throw UnknownCrmEntityViolation(
        entityName: 'CustomerNotificationCampaign',
        id: campaignId,
      );
    }
    if (existing.status != CustomerNotificationCampaignStatus.draft) {
      throw InvalidNotificationCampaignTransitionViolation(
        campaignId: campaignId,
        fromStatusName: existing.status.name,
      );
    }

    final updated = existing.copyWith(
      status: CustomerNotificationCampaignStatus.scheduled,
      scheduledFor: scheduledFor,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);
    return updated;
  }
}
