import '../../../../core/errors/business_rule_violation.dart';
import '../../data/customer_feedback_repository.dart';
import '../../data/customer_feedback_response_repository.dart';
import '../../data/customer_feedback_status_event_repository.dart';
import '../../domain/customer_feedback_view.dart';
import '../../domain/feedback_priority.dart';
import '../../domain/feedback_status.dart';

/// Assembles one ticket's [CustomerFeedbackView] — Sprint 5D. A pure
/// read-model builder: no authorization check (matches
/// `BuildCourierLiveStatus`'s established precedent — screen
/// reachability is the access gate).
class BuildCustomerFeedbackView {
  const BuildCustomerFeedbackView({
    required CustomerFeedbackRepository feedbackRepository,
    required CustomerFeedbackStatusEventRepository statusEventRepository,
    required CustomerFeedbackResponseRepository responseRepository,
  })  : _feedbackRepository = feedbackRepository,
        _statusEventRepository = statusEventRepository,
        _responseRepository = responseRepository;

  final CustomerFeedbackRepository _feedbackRepository;
  final CustomerFeedbackStatusEventRepository _statusEventRepository;
  final CustomerFeedbackResponseRepository _responseRepository;

  Future<CustomerFeedbackView> call({required String feedbackId}) async {
    final feedback = await _feedbackRepository.findById(feedbackId);
    if (feedback == null) {
      throw UnknownCrmEntityViolation(
        entityName: 'CustomerFeedback',
        id: feedbackId,
      );
    }

    final statusHistory =
        await _statusEventRepository.findByFeedbackId(feedbackId);
    final responses = await _responseRepository.findByFeedbackId(feedbackId);

    final latest = statusHistory.isEmpty ? null : statusHistory.last;

    return CustomerFeedbackView(
      feedback: feedback,
      currentStatus: latest?.status ?? FeedbackStatus.open,
      currentPriority: latest?.priority ?? FeedbackPriority.medium,
      statusHistory: statusHistory,
      responses: responses,
    );
  }
}
