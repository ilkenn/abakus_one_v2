import '../../../orders/domain/models/order_id.dart';
import '../../data/kitchen_event_repository.dart';
import '../../domain/kds/kitchen_event.dart';
import '../../domain/kds/kitchen_event_publisher.dart';
import '../../domain/kds/kitchen_event_type.dart';
import '../identity/kitchen_event_id_generator.dart';

/// Records one [KitchenEvent] — appends it to [KitchenEventRepository]
/// (structural duplicate-idempotency-key rejection lives there) then
/// publishes it via [KitchenEventPublisher] for any live subscriber.
/// Every other Phase 4 use case that needs to emit an event calls this
/// shared helper rather than duplicating the append-then-publish sequence.
class RecordKitchenEvent {
  const RecordKitchenEvent({
    required KitchenEventIdGenerator idGenerator,
    required KitchenEventRepository eventRepository,
    required KitchenEventPublisher eventPublisher,
  })  : _idGenerator = idGenerator,
        _eventRepository = eventRepository,
        _eventPublisher = eventPublisher;

  final KitchenEventIdGenerator _idGenerator;
  final KitchenEventRepository _eventRepository;
  final KitchenEventPublisher _eventPublisher;

  Future<KitchenEvent> call({
    required String branchId,
    OrderId? orderId,
    String? kitchenTicketId,
    String? workItemId,
    required KitchenEventType type,
    required String idempotencyKey,
    required DateTime occurredAt,
    String? sourceDeviceId,
    Map<String, String> payload = const {},
  }) async {
    final event = KitchenEvent(
      id: _idGenerator.nextEventId(),
      branchId: branchId,
      orderId: orderId,
      kitchenTicketId: kitchenTicketId,
      workItemId: workItemId,
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
