import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/crm_audit_entry_repository.dart';
import '../../data/customer_notification_campaign_repository.dart';
import '../../domain/audit/crm_audit_entry.dart';
import '../../domain/audit/crm_audit_event_type.dart';
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
///
/// **Sprint 5E**: audited via [CrmAuditEntry] (`docs/decisions.md`
/// ADR-022).
class ScheduleCustomerNotificationCampaign {
  const ScheduleCustomerNotificationCampaign({
    required PosAuthorizationPolicy authorizationPolicy,
    required CustomerNotificationCampaignRepository repository,
    required CrmAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final CustomerNotificationCampaignRepository _repository;
  final CrmAuditEntryRepository _auditRepository;

  Future<CustomerNotificationCampaign> call({
    required String campaignId,
    required DateTime scheduledFor,
    required String performedByStaffId,
    required DateTime performedAt,
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

    await _auditRepository.appendEvent(CrmAuditEntry(
      id: '$campaignId-audit-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: CrmAuditEventType.customerNotificationCampaignScheduled,
      description: 'Notification campaign scheduled for $scheduledFor',
      targetEntityId: campaignId,
      previousStateName: existing.status.name,
      newStateName: updated.status.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
