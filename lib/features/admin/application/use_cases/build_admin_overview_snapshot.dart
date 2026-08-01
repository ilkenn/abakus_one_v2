import '../../../../core/utils/clock.dart';
import '../../../courier/application/use_cases/build_courier_operation_health.dart';
import '../../../courier/data/courier_availability_repository.dart';
import '../../../courier/data/courier_repository.dart';
import '../../../courier/domain/availability/courier_availability_status.dart';
import '../../../crm/data/customer_notification_campaign_repository.dart';
import '../../../crm/data/survey_repository.dart';
import '../../../crm/domain/notifications/customer_notification_campaign_status.dart';
import '../../../feedback/data/customer_feedback_repository.dart';
import '../../../feedback/data/customer_feedback_status_event_repository.dart';
import '../../../feedback/domain/feedback_status.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/branch_repository.dart';
import '../../domain/organization/branch_status.dart';
import '../../domain/overview/admin_overview_snapshot.dart';

/// Builds [AdminOverviewSnapshot] — Phase 6E (`docs/decisions.md`
/// ADR-023), a pure read-model, computed fresh on every read, never
/// persisted (mirrors `BuildCourierLiveStatus`/`BuildCustomerVisitPassport`'s
/// "computed fresh" discipline).
///
/// **Deliberately omits**: an "open orders" count (no repository query
/// exists for it — `PosOrderRepository` has no `findOpen`-shaped method);
/// a standalone "delayed kitchen work" count independent of courier
/// operations (`KitchenProjectionRepository` has no such query either —
/// [operationHealth]'s delayed-delivery signal is the closest real
/// proxy, and only covers the delivery channel); "open cash sessions"
/// (no branch-scoped cash-session listing query exists). "Do not
/// fabricate metrics that have no data source" — these are honestly
/// absent, not approximated with a fake zero.
class BuildAdminOverviewSnapshot {
  const BuildAdminOverviewSnapshot({
    required Clock clock,
    required BranchRepository branchRepository,
    required CourierRepository courierRepository,
    required CourierAvailabilityRepository courierAvailabilityRepository,
    required BuildCourierOperationHealth buildCourierOperationHealth,
    required CustomerFeedbackRepository feedbackRepository,
    required CustomerFeedbackStatusEventRepository
        feedbackStatusEventRepository,
    required SurveyRepository surveyRepository,
    required CustomerNotificationCampaignRepository campaignRepository,
    required AdminAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _branchRepository = branchRepository,
        _courierRepository = courierRepository,
        _courierAvailabilityRepository = courierAvailabilityRepository,
        _buildCourierOperationHealth = buildCourierOperationHealth,
        _feedbackRepository = feedbackRepository,
        _feedbackStatusEventRepository = feedbackStatusEventRepository,
        _surveyRepository = surveyRepository,
        _campaignRepository = campaignRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final BranchRepository _branchRepository;
  final CourierRepository _courierRepository;
  final CourierAvailabilityRepository _courierAvailabilityRepository;
  final BuildCourierOperationHealth _buildCourierOperationHealth;
  final CustomerFeedbackRepository _feedbackRepository;
  final CustomerFeedbackStatusEventRepository _feedbackStatusEventRepository;
  final SurveyRepository _surveyRepository;
  final CustomerNotificationCampaignRepository _campaignRepository;
  final AdminAuditEntryRepository _auditRepository;

  Future<AdminOverviewSnapshot> call({required String branchId}) async {
    final now = _clock.now();

    final branches = await _branchRepository.findAll();
    final activeBranchCount =
        branches.where((b) => b.status == BranchStatus.active).length;

    final courierHealth =
        await _buildCourierOperationHealth(branchId: branchId);

    final couriers = await _courierRepository.findByBranchId(branchId);
    var activeCourierCount = 0;
    for (final courier in couriers) {
      final availability =
          await _courierAvailabilityRepository.findByCourierId(courier.id);
      if (availability != null &&
          availability.status != CourierAvailabilityStatus.offline) {
        activeCourierCount++;
      }
    }

    final feedbackTickets = await _feedbackRepository.findByBranchId(branchId);
    var unresolvedFeedbackCount = 0;
    for (final ticket in feedbackTickets) {
      final events =
          await _feedbackStatusEventRepository.findByFeedbackId(ticket.id);
      if (events.isEmpty) continue;
      final currentStatus = events.last.status;
      if (currentStatus != FeedbackStatus.resolved &&
          currentStatus != FeedbackStatus.closed) {
        unresolvedFeedbackCount++;
      }
    }

    final surveys = await _surveyRepository.findAll();
    final pendingSurveyCount = surveys.where((s) => s.isActive).length;

    final campaigns = await _campaignRepository.findAll();
    final pendingCampaignCount = campaigns
        .where((c) =>
            c.status == CustomerNotificationCampaignStatus.draft ||
            c.status == CustomerNotificationCampaignStatus.scheduled)
        .length;

    final auditEntries = await _auditRepository.findAll();
    final recentAudit = auditEntries.reversed
        .take(5)
        .map((e) => e.description)
        .toList(growable: false);

    return AdminOverviewSnapshot(
      activeBranchCount: activeBranchCount,
      waitingDeliveryCount: courierHealth.waitingDeliveryCount,
      activeCourierCount: activeCourierCount,
      unresolvedFeedbackCount: unresolvedFeedbackCount,
      pendingSurveyCount: pendingSurveyCount,
      pendingCampaignCount: pendingCampaignCount,
      operationHealth: courierHealth,
      recentCriticalAuditDescriptions: recentAudit,
      generatedAt: now,
    );
  }
}
