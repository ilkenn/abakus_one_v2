import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/customer_feedback_repository.dart';
import '../../data/customer_feedback_status_event_repository.dart';
import '../../domain/customer_feedback.dart';
import '../../domain/customer_feedback_status_event.dart';
import '../../domain/feedback_category.dart';
import '../../domain/feedback_priority.dart';
import '../../domain/feedback_status.dart';
import '../identity/customer_feedback_id_generator.dart';
import '../identity/customer_feedback_status_event_id_generator.dart';

/// A customer submits [CustomerFeedback] — no authorization gate (a
/// customer's own submission). Also appends the ticket's automatic
/// initial [CustomerFeedbackStatusEvent] ([FeedbackStatus.open],
/// [FeedbackPriority.medium], `changedByStaffId: null` — a
/// system-recorded fact, not an administrator decision).
class SubmitCustomerFeedback {
  const SubmitCustomerFeedback({
    required Clock clock,
    required CustomerFeedbackIdGenerator feedbackIdGenerator,
    required CustomerFeedbackStatusEventIdGenerator statusEventIdGenerator,
    required CustomerFeedbackRepository feedbackRepository,
    required CustomerFeedbackStatusEventRepository statusEventRepository,
  })  : _clock = clock,
        _feedbackIdGenerator = feedbackIdGenerator,
        _statusEventIdGenerator = statusEventIdGenerator,
        _feedbackRepository = feedbackRepository,
        _statusEventRepository = statusEventRepository;

  final Clock _clock;
  final CustomerFeedbackIdGenerator _feedbackIdGenerator;
  final CustomerFeedbackStatusEventIdGenerator _statusEventIdGenerator;
  final CustomerFeedbackRepository _feedbackRepository;
  final CustomerFeedbackStatusEventRepository _statusEventRepository;

  Future<CustomerFeedback> call({
    String? customerId,
    required String branchId,
    required FeedbackCategory category,
    required String subject,
    required String body,
    List<String> attachmentRefs = const [],
  }) async {
    if (subject.trim().isEmpty) {
      throw const InvalidCustomerFeedbackViolation(
        reason: 'subject must not be empty',
      );
    }
    if (body.trim().isEmpty) {
      throw const InvalidCustomerFeedbackViolation(
        reason: 'body must not be empty',
      );
    }

    final now = _clock.now();
    final feedback = CustomerFeedback(
      id: _feedbackIdGenerator.nextFeedbackId(),
      customerId: customerId,
      branchId: branchId,
      category: category,
      subject: subject,
      body: body,
      attachmentRefs: attachmentRefs,
      submittedAt: now,
    );
    await _feedbackRepository.append(feedback);

    await _statusEventRepository.append(CustomerFeedbackStatusEvent(
      id: _statusEventIdGenerator.nextEventId(),
      feedbackId: feedback.id,
      status: FeedbackStatus.open,
      priority: FeedbackPriority.medium,
      occurredAt: now,
    ));

    return feedback;
  }
}
