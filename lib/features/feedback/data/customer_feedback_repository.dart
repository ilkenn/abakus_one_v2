import '../domain/customer_feedback.dart';

/// Append-only storage for [CustomerFeedback] — no update or delete
/// method exists at all.
abstract interface class CustomerFeedbackRepository {
  Future<void> append(CustomerFeedback feedback);
  Future<CustomerFeedback?> findById(String feedbackId);
  Future<List<CustomerFeedback>> findByBranchId(String branchId);
  Future<List<CustomerFeedback>> findByCustomerId(String customerId);
}

class InMemoryCustomerFeedbackRepository implements CustomerFeedbackRepository {
  final List<CustomerFeedback> _feedback = [];

  @override
  Future<void> append(CustomerFeedback feedback) async {
    _feedback.add(feedback);
  }

  @override
  Future<CustomerFeedback?> findById(String feedbackId) async {
    for (final feedback in _feedback) {
      if (feedback.id == feedbackId) return feedback;
    }
    return null;
  }

  @override
  Future<List<CustomerFeedback>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _feedback.where((f) => f.branchId == branchId),
    );
  }

  @override
  Future<List<CustomerFeedback>> findByCustomerId(String customerId) async {
    return List.unmodifiable(
      _feedback.where((f) => f.customerId == customerId),
    );
  }
}
