import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/feedback/application/use_cases/build_customer_feedback_view.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_repository.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_response_repository.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_status_event_repository.dart';
import 'package:abakus_one_v2/features/feedback/domain/customer_feedback.dart';
import 'package:abakus_one_v2/features/feedback/domain/customer_feedback_response.dart';
import 'package:abakus_one_v2/features/feedback/domain/customer_feedback_status_event.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_category.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_priority.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_status.dart';
import 'package:flutter_test/flutter_test.dart';

CustomerFeedback _buildFeedback() {
  return CustomerFeedback(
    id: 'feedback-1',
    branchId: 'branch-1',
    category: FeedbackCategory.complaint,
    subject: 'Sipariş gecikti',
    body: 'Siparişim çok geç geldi.',
    submittedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('BuildCustomerFeedbackView', () {
    test('reflects the latest status event as current status/priority',
        () async {
      final feedbackRepository = InMemoryCustomerFeedbackRepository();
      await feedbackRepository.append(_buildFeedback());
      final statusEventRepository =
          InMemoryCustomerFeedbackStatusEventRepository();
      await statusEventRepository.append(CustomerFeedbackStatusEvent(
        id: 'event-0',
        feedbackId: 'feedback-1',
        status: FeedbackStatus.open,
        priority: FeedbackPriority.medium,
        occurredAt: DateTime(2026, 1, 1),
      ));
      await statusEventRepository.append(CustomerFeedbackStatusEvent(
        id: 'event-1',
        feedbackId: 'feedback-1',
        status: FeedbackStatus.resolved,
        priority: FeedbackPriority.low,
        changedByStaffId: 'manager-1',
        occurredAt: DateTime(2026, 1, 3),
      ));
      final responseRepository = InMemoryCustomerFeedbackResponseRepository();
      await responseRepository.append(CustomerFeedbackResponse(
        id: 'response-1',
        feedbackId: 'feedback-1',
        respondedByStaffId: 'manager-1',
        responseText: 'Özür dileriz.',
        respondedAt: DateTime(2026, 1, 2),
      ));

      final useCase = BuildCustomerFeedbackView(
        feedbackRepository: feedbackRepository,
        statusEventRepository: statusEventRepository,
        responseRepository: responseRepository,
      );

      final view = await useCase(feedbackId: 'feedback-1');

      expect(view.currentStatus, FeedbackStatus.resolved);
      expect(view.currentPriority, FeedbackPriority.low);
      expect(view.statusHistory, hasLength(2));
      expect(view.responses, hasLength(1));
    });

    test('an unknown feedback id throws UnknownCrmEntityViolation', () async {
      final useCase = BuildCustomerFeedbackView(
        feedbackRepository: InMemoryCustomerFeedbackRepository(),
        statusEventRepository: InMemoryCustomerFeedbackStatusEventRepository(),
        responseRepository: InMemoryCustomerFeedbackResponseRepository(),
      );

      expect(
        () => useCase(feedbackId: 'missing'),
        throwsA(isA<UnknownCrmEntityViolation>()),
      );
    });
  });
}
