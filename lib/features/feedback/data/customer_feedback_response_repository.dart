import '../domain/customer_feedback_response.dart';

/// Append-only storage for [CustomerFeedbackResponse] — no update or
/// delete method exists at all.
abstract interface class CustomerFeedbackResponseRepository {
  Future<void> append(CustomerFeedbackResponse response);
  Future<List<CustomerFeedbackResponse>> findByFeedbackId(String feedbackId);
}

class InMemoryCustomerFeedbackResponseRepository
    implements CustomerFeedbackResponseRepository {
  final List<CustomerFeedbackResponse> _responses = [];

  @override
  Future<void> append(CustomerFeedbackResponse response) async {
    _responses.add(response);
  }

  @override
  Future<List<CustomerFeedbackResponse>> findByFeedbackId(
      String feedbackId) async {
    return List.unmodifiable(
      _responses.where((r) => r.feedbackId == feedbackId),
    );
  }
}
