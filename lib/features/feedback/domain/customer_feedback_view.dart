import 'customer_feedback.dart';
import 'customer_feedback_response.dart';
import 'customer_feedback_status_event.dart';
import 'feedback_priority.dart';
import 'feedback_status.dart';

/// One feedback ticket's assembled view — Sprint 5D. Computed fresh on
/// every read by `BuildCustomerFeedbackView`, never persisted itself:
/// combines the immutable [feedback] core with the *latest*
/// [CustomerFeedbackStatusEvent] (for [currentStatus]/[currentPriority])
/// and the full [responses]/[statusHistory] trails.
class CustomerFeedbackView {
  const CustomerFeedbackView({
    required this.feedback,
    required this.currentStatus,
    required this.currentPriority,
    required this.statusHistory,
    required this.responses,
  });

  final CustomerFeedback feedback;
  final FeedbackStatus currentStatus;
  final FeedbackPriority currentPriority;

  /// Oldest first — the full triage audit trail.
  final List<CustomerFeedbackStatusEvent> statusHistory;

  final List<CustomerFeedbackResponse> responses;
}
