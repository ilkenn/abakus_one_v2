import '../domain/feedback/courier_feedback.dart';

/// Append-only storage for [CourierFeedback].
abstract interface class CourierFeedbackRepository {
  Future<void> append(CourierFeedback feedback);
  Future<List<CourierFeedback>> findByDeliveryId(String deliveryId);
}

class InMemoryCourierFeedbackRepository implements CourierFeedbackRepository {
  final List<CourierFeedback> _feedback = [];

  @override
  Future<void> append(CourierFeedback feedback) async {
    _feedback.add(feedback);
  }

  @override
  Future<List<CourierFeedback>> findByDeliveryId(String deliveryId) async {
    return List.unmodifiable(
      _feedback.where((f) => f.deliveryId == deliveryId),
    );
  }
}
