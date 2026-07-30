import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_message_status_event_repository.dart';
import '../../domain/communication/courier_message_status_event.dart';
import '../identity/courier_message_status_event_id_generator.dart';

/// Records that one courier's device delivered or read a [CourierMessage]
/// — Sprint 5C Part 8. System-triggered, no authorization gate — routine
/// device telemetry, mirrors `RecordCourierLocationSnapshot`'s own
/// precedent exactly. Acknowledgement (emergency messages only) is a
/// separate, distinct use case — `AcknowledgeEmergencyMessage` — since it
/// carries its own validation (only an emergency message accepts one).
class RecordCourierMessageStatus {
  const RecordCourierMessageStatus({
    required Clock clock,
    required CourierMessageStatusEventIdGenerator idGenerator,
    required CourierMessageStatusEventRepository repository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _repository = repository;

  final Clock _clock;
  final CourierMessageStatusEventIdGenerator _idGenerator;
  final CourierMessageStatusEventRepository _repository;

  Future<CourierMessageStatusEvent> call({
    required String messageId,
    required String courierId,
    required CourierMessageStatusEventType type,
  }) async {
    if (type == CourierMessageStatusEventType.acknowledged) {
      throw MessageAcknowledgementNotRequiredViolation(messageId: messageId);
    }
    final event = CourierMessageStatusEvent(
      id: _idGenerator.nextStatusEventId(),
      messageId: messageId,
      courierId: courierId,
      type: type,
      occurredAt: _clock.now(),
    );
    await _repository.append(event);
    return event;
  }
}
