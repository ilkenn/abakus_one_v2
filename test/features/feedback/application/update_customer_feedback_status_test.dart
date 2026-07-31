import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/feedback/application/identity/customer_feedback_status_event_id_generator.dart';
import 'package:abakus_one_v2/features/feedback/application/use_cases/update_customer_feedback_status.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_repository.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_status_event_repository.dart';
import 'package:abakus_one_v2/features/feedback/domain/customer_feedback.dart';
import 'package:abakus_one_v2/features/feedback/domain/customer_feedback_status_event.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_category.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_priority.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../test_support/feedback_test_fixtures.dart';

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
  group('UpdateCustomerFeedbackStatus', () {
    test('moves an open ticket to inReview and keeps priority when omitted',
        () async {
      final feedbackRepository = InMemoryCustomerFeedbackRepository();
      await feedbackRepository.append(_buildFeedback());
      final statusEventRepository =
          InMemoryCustomerFeedbackStatusEventRepository();
      await statusEventRepository.append(CustomerFeedbackStatusEvent(
        id: 'event-0',
        feedbackId: 'feedback-1',
        status: FeedbackStatus.open,
        priority: FeedbackPriority.high,
        occurredAt: DateTime(2026, 1, 1),
      ));
      final useCase = UpdateCustomerFeedbackStatus(
        clock: FakeClock(DateTime(2026, 1, 2)),
        authorizationPolicy: const AllowAllFeedbackPolicy(),
        idGenerator: SequentialCustomerFeedbackStatusEventIdGenerator(),
        feedbackRepository: feedbackRepository,
        statusEventRepository: statusEventRepository,
      );

      final event = await useCase(
        feedbackId: 'feedback-1',
        status: FeedbackStatus.inReview,
        performedByStaffId: 'manager-1',
      );

      expect(event.status, FeedbackStatus.inReview);
      expect(event.priority, FeedbackPriority.high);
      expect(event.changedByStaffId, 'manager-1');
    });

    test('an explicit priority overrides the carried-forward value', () async {
      final feedbackRepository = InMemoryCustomerFeedbackRepository();
      await feedbackRepository.append(_buildFeedback());
      final statusEventRepository =
          InMemoryCustomerFeedbackStatusEventRepository();
      final useCase = UpdateCustomerFeedbackStatus(
        clock: FakeClock(DateTime(2026, 1, 2)),
        authorizationPolicy: const AllowAllFeedbackPolicy(),
        idGenerator: SequentialCustomerFeedbackStatusEventIdGenerator(),
        feedbackRepository: feedbackRepository,
        statusEventRepository: statusEventRepository,
      );

      final event = await useCase(
        feedbackId: 'feedback-1',
        status: FeedbackStatus.resolved,
        priority: FeedbackPriority.low,
        performedByStaffId: 'manager-1',
      );

      expect(event.priority, FeedbackPriority.low);
    });

    test('an unknown feedback id throws UnknownCrmEntityViolation', () async {
      final useCase = UpdateCustomerFeedbackStatus(
        clock: FakeClock(DateTime(2026, 1, 2)),
        authorizationPolicy: const AllowAllFeedbackPolicy(),
        idGenerator: SequentialCustomerFeedbackStatusEventIdGenerator(),
        feedbackRepository: InMemoryCustomerFeedbackRepository(),
        statusEventRepository: InMemoryCustomerFeedbackStatusEventRepository(),
      );

      expect(
        () => useCase(
          feedbackId: 'missing',
          status: FeedbackStatus.resolved,
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<UnknownCrmEntityViolation>()),
      );
    });

    test('an unauthorized actor cannot update status', () async {
      final feedbackRepository = InMemoryCustomerFeedbackRepository();
      await feedbackRepository.append(_buildFeedback());
      final useCase = UpdateCustomerFeedbackStatus(
        clock: FakeClock(DateTime(2026, 1, 2)),
        authorizationPolicy: const DenyAllFeedbackPolicy(),
        idGenerator: SequentialCustomerFeedbackStatusEventIdGenerator(),
        feedbackRepository: feedbackRepository,
        statusEventRepository: InMemoryCustomerFeedbackStatusEventRepository(),
      );

      expect(
        () => useCase(
          feedbackId: 'feedback-1',
          status: FeedbackStatus.resolved,
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
