import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/feedback/application/identity/customer_feedback_response_id_generator.dart';
import 'package:abakus_one_v2/features/feedback/application/use_cases/respond_to_customer_feedback.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_repository.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_response_repository.dart';
import 'package:abakus_one_v2/features/feedback/domain/customer_feedback.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_category.dart';
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
  group('RespondToCustomerFeedback', () {
    test('appends a response to an existing ticket', () async {
      final feedbackRepository = InMemoryCustomerFeedbackRepository();
      await feedbackRepository.append(_buildFeedback());
      final responseRepository = InMemoryCustomerFeedbackResponseRepository();
      final useCase = RespondToCustomerFeedback(
        clock: FakeClock(DateTime(2026, 1, 2)),
        authorizationPolicy: const AllowAllFeedbackPolicy(),
        idGenerator: SequentialCustomerFeedbackResponseIdGenerator(),
        feedbackRepository: feedbackRepository,
        responseRepository: responseRepository,
      );

      final response = await useCase(
        feedbackId: 'feedback-1',
        responseText: 'Özür dileriz, ilgileniyoruz.',
        performedByStaffId: 'manager-1',
      );

      expect(
        await responseRepository.findByFeedbackId('feedback-1'),
        [response],
      );
    });

    test('an unknown feedback id throws UnknownCrmEntityViolation', () async {
      final useCase = RespondToCustomerFeedback(
        clock: FakeClock(DateTime(2026, 1, 2)),
        authorizationPolicy: const AllowAllFeedbackPolicy(),
        idGenerator: SequentialCustomerFeedbackResponseIdGenerator(),
        feedbackRepository: InMemoryCustomerFeedbackRepository(),
        responseRepository: InMemoryCustomerFeedbackResponseRepository(),
      );

      expect(
        () => useCase(
          feedbackId: 'missing',
          responseText: 'Merhaba',
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<UnknownCrmEntityViolation>()),
      );
    });

    test('an unauthorized actor cannot respond', () async {
      final feedbackRepository = InMemoryCustomerFeedbackRepository();
      await feedbackRepository.append(_buildFeedback());
      final useCase = RespondToCustomerFeedback(
        clock: FakeClock(DateTime(2026, 1, 2)),
        authorizationPolicy: const DenyAllFeedbackPolicy(),
        idGenerator: SequentialCustomerFeedbackResponseIdGenerator(),
        feedbackRepository: feedbackRepository,
        responseRepository: InMemoryCustomerFeedbackResponseRepository(),
      );

      expect(
        () => useCase(
          feedbackId: 'feedback-1',
          responseText: 'Merhaba',
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
