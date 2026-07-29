import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_feedback_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/feedback/courier_feedback.dart';
import '../../domain/feedback/courier_feedback_tag.dart';
import '../identity/courier_feedback_id_generator.dart';

/// Records courier feedback for a delivery — **predefined
/// [CourierFeedbackTag]s only**; at least one tag is required. [note] is
/// operational and length-limited (280 characters, enforced here).
class RecordCourierFeedback {
  const RecordCourierFeedback({
    required Clock clock,
    required CourierFeedbackIdGenerator idGenerator,
    required DeliveryRepository deliveryRepository,
    required CourierFeedbackRepository feedbackRepository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _deliveryRepository = deliveryRepository,
        _feedbackRepository = feedbackRepository;

  final Clock _clock;
  final CourierFeedbackIdGenerator _idGenerator;
  final DeliveryRepository _deliveryRepository;
  final CourierFeedbackRepository _feedbackRepository;

  static const _maxNoteLength = 280;

  Future<CourierFeedback> call({
    required String deliveryId,
    required String courierId,
    required List<CourierFeedbackTag> tags,
    String note = '',
  }) async {
    final delivery = await _deliveryRepository.findById(deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: deliveryId,
      );
    }
    if (tags.isEmpty) {
      throw InvalidCourierFeedbackViolation(deliveryId: deliveryId);
    }

    final truncatedNote =
        note.length > _maxNoteLength ? note.substring(0, _maxNoteLength) : note;

    final feedback = CourierFeedback(
      id: _idGenerator.nextFeedbackId(),
      deliveryId: deliveryId,
      courierId: courierId,
      tags: List.unmodifiable(tags),
      note: truncatedNote,
      recordedAt: _clock.now(),
    );
    await _feedbackRepository.append(feedback);
    return feedback;
  }
}
