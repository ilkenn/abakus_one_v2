import 'courier_feedback_tag.dart';

/// One immutable, append-only courier feedback record for a delivery.
/// [note] is length-limited (enforced by `RecordCourierFeedback`, max 280
/// characters) — never an unrestricted free-text field.
class CourierFeedback {
  const CourierFeedback({
    required this.id,
    required this.deliveryId,
    required this.courierId,
    required this.tags,
    this.note = '',
    required this.recordedAt,
  });

  final String id;
  final String deliveryId;
  final String courierId;
  final List<CourierFeedbackTag> tags;
  final String note;
  final DateTime recordedAt;
}
