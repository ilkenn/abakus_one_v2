import '../../data/courier_event_repository.dart';
import '../../domain/events/courier_event.dart';
import '../../domain/events/courier_event_publisher.dart';
import '../../domain/events/courier_event_type.dart';
import '../identity/courier_event_id_generator.dart';

/// Records one [CourierEvent] — appends then publishes — mirrors
/// `RecordKitchenEvent`'s shape exactly (Phase 4). Every other use case in
/// this feature that needs to emit an event calls this shared helper.
class RecordCourierEvent {
  const RecordCourierEvent({
    required CourierEventIdGenerator idGenerator,
    required CourierEventRepository eventRepository,
    required CourierEventPublisher eventPublisher,
  })  : _idGenerator = idGenerator,
        _eventRepository = eventRepository,
        _eventPublisher = eventPublisher;

  final CourierEventIdGenerator _idGenerator;
  final CourierEventRepository _eventRepository;
  final CourierEventPublisher _eventPublisher;

  Future<CourierEvent> call({
    required String branchId,
    String? courierId,
    String? deliveryId,
    String? assignmentId,
    String? shiftId,
    required CourierEventType type,
    required String idempotencyKey,
    required DateTime occurredAt,
    String? sourceDeviceId,
    Map<String, String> payload = const {},
  }) async {
    final event = CourierEvent(
      id: _idGenerator.nextEventId(),
      branchId: branchId,
      courierId: courierId,
      deliveryId: deliveryId,
      assignmentId: assignmentId,
      shiftId: shiftId,
      type: type,
      idempotencyKey: idempotencyKey,
      sequence: 0,
      occurredAt: occurredAt,
      sourceDeviceId: sourceDeviceId,
      payload: payload,
    );
    final stored = await _eventRepository.append(event);
    await _eventPublisher.publish(stored);
    return stored;
  }
}
