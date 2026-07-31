import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/feedback/application/identity/customer_feedback_id_generator.dart';
import 'package:abakus_one_v2/features/feedback/application/identity/customer_feedback_status_event_id_generator.dart';
import 'package:abakus_one_v2/features/feedback/application/use_cases/submit_customer_feedback.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_repository.dart';
import 'package:abakus_one_v2/features/feedback/data/customer_feedback_status_event_repository.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_category.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_priority.dart';
import 'package:abakus_one_v2/features/feedback/domain/feedback_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

void main() {
  group('SubmitCustomerFeedback', () {
    SubmitCustomerFeedback buildUseCase({
      required CustomerFeedbackRepository feedbackRepository,
      required CustomerFeedbackStatusEventRepository statusEventRepository,
    }) {
      return SubmitCustomerFeedback(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        feedbackIdGenerator: SequentialCustomerFeedbackIdGenerator(),
        statusEventIdGenerator:
            SequentialCustomerFeedbackStatusEventIdGenerator(),
        feedbackRepository: feedbackRepository,
        statusEventRepository: statusEventRepository,
      );
    }

    test('submits feedback and seeds an initial open/medium status event',
        () async {
      final feedbackRepository = InMemoryCustomerFeedbackRepository();
      final statusEventRepository =
          InMemoryCustomerFeedbackStatusEventRepository();
      final useCase = buildUseCase(
        feedbackRepository: feedbackRepository,
        statusEventRepository: statusEventRepository,
      );

      final feedback = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        category: FeedbackCategory.complaint,
        subject: 'Sipariş gecikti',
        body: 'Siparişim çok geç geldi.',
      );

      expect(await feedbackRepository.findById(feedback.id), feedback);
      final history = await statusEventRepository.findByFeedbackId(feedback.id);
      expect(history, hasLength(1));
      expect(history.first.status, FeedbackStatus.open);
      expect(history.first.priority, FeedbackPriority.medium);
      expect(history.first.changedByStaffId, isNull);
    });

    test('allows submission without a customerId (anonymous)', () async {
      final useCase = buildUseCase(
        feedbackRepository: InMemoryCustomerFeedbackRepository(),
        statusEventRepository: InMemoryCustomerFeedbackStatusEventRepository(),
      );

      final feedback = await useCase(
        branchId: 'branch-1',
        category: FeedbackCategory.suggestion,
        subject: 'Menü önerisi',
        body: 'Vegan seçenek eklenebilir mi?',
      );

      expect(feedback.customerId, isNull);
    });

    test('rejects an empty subject', () async {
      final useCase = buildUseCase(
        feedbackRepository: InMemoryCustomerFeedbackRepository(),
        statusEventRepository: InMemoryCustomerFeedbackStatusEventRepository(),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          category: FeedbackCategory.generalFeedback,
          subject: '   ',
          body: 'Yorum',
        ),
        throwsA(isA<InvalidCustomerFeedbackViolation>()),
      );
    });

    test('rejects an empty body', () async {
      final useCase = buildUseCase(
        feedbackRepository: InMemoryCustomerFeedbackRepository(),
        statusEventRepository: InMemoryCustomerFeedbackStatusEventRepository(),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          category: FeedbackCategory.generalFeedback,
          subject: 'Konu',
          body: '',
        ),
        throwsA(isA<InvalidCustomerFeedbackViolation>()),
      );
    });
  });
}
