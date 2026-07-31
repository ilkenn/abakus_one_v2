import '../domain/customer_feedback_status_event.dart';

/// Append-only storage for [CustomerFeedbackStatusEvent] — no update or
/// delete method exists at all.
abstract interface class CustomerFeedbackStatusEventRepository {
  Future<void> append(CustomerFeedbackStatusEvent event);
  Future<List<CustomerFeedbackStatusEvent>> findByFeedbackId(String feedbackId);
}

class InMemoryCustomerFeedbackStatusEventRepository
    implements CustomerFeedbackStatusEventRepository {
  final List<CustomerFeedbackStatusEvent> _events = [];

  @override
  Future<void> append(CustomerFeedbackStatusEvent event) async {
    _events.add(event);
  }

  @override
  Future<List<CustomerFeedbackStatusEvent>> findByFeedbackId(
      String feedbackId) async {
    return List.unmodifiable(
      _events.where((e) => e.feedbackId == feedbackId),
    );
  }
}
