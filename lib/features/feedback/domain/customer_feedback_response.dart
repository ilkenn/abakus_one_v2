/// One immutable, append-only administrator response to a
/// [CustomerFeedback] ticket — "admin response," Sprint 5D's Customer
/// Feedback Center. A ticket may accumulate multiple responses over time;
/// none is ever edited or deleted.
class CustomerFeedbackResponse {
  const CustomerFeedbackResponse({
    required this.id,
    required this.feedbackId,
    required this.respondedByStaffId,
    required this.responseText,
    required this.respondedAt,
  });

  final String id;
  final String feedbackId;
  final String respondedByStaffId;
  final String responseText;
  final DateTime respondedAt;
}
