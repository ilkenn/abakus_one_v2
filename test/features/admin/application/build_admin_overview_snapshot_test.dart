import 'package:abakus_one_v2/features/admin/application/use_cases/build_admin_overview_snapshot.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/branch_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/branch.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/branch_status.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_operation_health.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_live_warnings.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_live_status.dart';
import 'package:abakus_one_v2/features/courier/data/courier_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_fraud_signal_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/application/services/in_memory_courier_connection_monitor.dart';
import 'package:abakus_one_v2/features/courier/data/courier_device_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_device_session_repository.dart';
import 'package:abakus_one_v2/features/crm/data/customer_notification_campaign_repository.dart';
import 'package:abakus_one_v2/features/crm/data/survey_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/notifications/customer_notification_campaign.dart';
import 'package:abakus_one_v2/features/crm/domain/notifications/customer_notification_campaign_status.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_question.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_question_type.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_repository.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_status_event_repository.dart';
import 'package:abakus_one_v2/features/feedback/domain/customer_feedback.dart';
import 'package:abakus_one_v2/features/feedback/domain/customer_feedback_status_event.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_category.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_priority.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

void main() {
  test('aggregates real branch/feedback/survey/campaign counts', () async {
    final branchRepository = InMemoryBranchRepository(seed: [
      Branch(
        id: 'branch-1',
        restaurantId: 'restaurant-1',
        name: 'Merkez',
        status: BranchStatus.active,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ),
      Branch(
        id: 'branch-2',
        restaurantId: 'restaurant-1',
        name: 'Kapalı Şube',
        status: BranchStatus.inactive,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ),
    ]);

    final feedbackRepository = InMemoryCustomerFeedbackRepository();
    final statusEventRepository =
        InMemoryCustomerFeedbackStatusEventRepository();
    await feedbackRepository.append(CustomerFeedback(
      id: 'fb-1',
      branchId: 'branch-1',
      category: FeedbackCategory.complaint,
      subject: 'Sorun',
      body: 'Detay',
      submittedAt: DateTime(2026, 1, 1),
    ));
    await statusEventRepository.append(CustomerFeedbackStatusEvent(
      id: 'fb-1-event-1',
      feedbackId: 'fb-1',
      status: FeedbackStatus.open,
      priority: FeedbackPriority.medium,
      occurredAt: DateTime(2026, 1, 1),
    ));
    await feedbackRepository.append(CustomerFeedback(
      id: 'fb-2',
      branchId: 'branch-1',
      category: FeedbackCategory.suggestion,
      subject: 'Öneri',
      body: 'Detay',
      submittedAt: DateTime(2026, 1, 1),
    ));
    await statusEventRepository.append(CustomerFeedbackStatusEvent(
      id: 'fb-2-event-1',
      feedbackId: 'fb-2',
      status: FeedbackStatus.resolved,
      priority: FeedbackPriority.low,
      changedByStaffId: 'manager-1',
      occurredAt: DateTime(2026, 1, 2),
    ));

    final surveyRepository = InMemorySurveyRepository();
    await surveyRepository.save(Survey(
      id: 'survey-1',
      title: 'Memnuniyet',
      questions: const [
        SurveyQuestion(
            id: 'q1', type: SurveyQuestionType.rating, prompt: 'Puan?'),
      ],
      activeFrom: DateTime(2026, 1, 1),
      isActive: true,
      createdByStaffId: 'manager-1',
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    ));

    final campaignRepository = InMemoryCustomerNotificationCampaignRepository();
    await campaignRepository.save(CustomerNotificationCampaign(
      id: 'campaign-1',
      title: 'Hoş Geldin',
      body: 'Mesaj',
      status: CustomerNotificationCampaignStatus.draft,
      createdByStaffId: 'manager-1',
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    ));

    final courierRepository = InMemoryCourierRepository();
    final availabilityRepository = InMemoryCourierAvailabilityRepository();
    final deliveryRepository = InMemoryDeliveryRepository();
    final auditRepository = InMemoryAdminAuditEntryRepository();

    final buildHealth = BuildCourierOperationHealth(
      clock: FakeClock(DateTime(2026, 1, 5)),
      deliveryRepository: deliveryRepository,
      buildCourierLiveWarnings: BuildCourierLiveWarnings(
        clock: FakeClock(DateTime(2026, 1, 5)),
        courierRepository: courierRepository,
        buildCourierLiveStatus: BuildCourierLiveStatus(
          clock: FakeClock(DateTime(2026, 1, 5)),
          locationRepository: InMemoryCourierLocationRepository(),
          connectionMonitor: InMemoryCourierConnectionMonitor(
            sessionRepository: InMemoryCourierDeviceSessionRepository(),
            deviceRepository: InMemoryCourierDeviceRepository(),
            courierRepository: courierRepository,
          ),
          availabilityRepository: availabilityRepository,
          locationAvailabilityRepository:
              InMemoryCourierLocationAvailabilityRepository(),
          deliveryRepository: deliveryRepository,
        ),
        locationAvailabilityRepository:
            InMemoryCourierLocationAvailabilityRepository(),
        fraudSignalRepository: InMemoryCourierFraudSignalRepository(),
      ),
    );

    final useCase = BuildAdminOverviewSnapshot(
      clock: FakeClock(DateTime(2026, 1, 5)),
      branchRepository: branchRepository,
      courierRepository: courierRepository,
      courierAvailabilityRepository: availabilityRepository,
      buildCourierOperationHealth: buildHealth,
      feedbackRepository: feedbackRepository,
      feedbackStatusEventRepository: statusEventRepository,
      surveyRepository: surveyRepository,
      campaignRepository: campaignRepository,
      auditRepository: auditRepository,
    );

    final snapshot = await useCase(branchId: 'branch-1');

    expect(snapshot.activeBranchCount, 1);
    expect(snapshot.unresolvedFeedbackCount, 1);
    expect(snapshot.pendingSurveyCount, 1);
    expect(snapshot.pendingCampaignCount, 1);
  });
}
