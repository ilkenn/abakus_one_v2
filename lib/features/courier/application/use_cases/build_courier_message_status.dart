import '../../data/courier_message_status_event_repository.dart';
import '../../domain/communication/courier_message_delivery_status.dart';
import '../../domain/communication/courier_message_status_event.dart';

/// Assembles per-courier delivered/read/acknowledged progress for one
/// [CourierMessage] — Sprint 5C Part 8's "manager sees delivered, read,
/// acknowledged, timestamp." A pure read-model builder over the existing,
/// unmodified `CourierMessageStatusEventRepository`.
class BuildCourierMessageStatus {
  const BuildCourierMessageStatus({
    required CourierMessageStatusEventRepository repository,
  }) : _repository = repository;

  final CourierMessageStatusEventRepository _repository;

  Future<List<CourierMessageDeliveryStatus>> call({
    required String messageId,
  }) async {
    final events = await _repository.findByMessageId(messageId);
    final byCourier = <String, List<CourierMessageStatusEvent>>{};
    for (final event in events) {
      byCourier.putIfAbsent(event.courierId, () => []).add(event);
    }

    DateTime? findAt(
      List<CourierMessageStatusEvent> events,
      CourierMessageStatusEventType type,
    ) {
      for (final event in events) {
        if (event.type == type) return event.occurredAt;
      }
      return null;
    }

    return [
      for (final entry in byCourier.entries)
        CourierMessageDeliveryStatus(
          messageId: messageId,
          courierId: entry.key,
          deliveredAt:
              findAt(entry.value, CourierMessageStatusEventType.delivered),
          readAt: findAt(entry.value, CourierMessageStatusEventType.read),
          acknowledgedAt:
              findAt(entry.value, CourierMessageStatusEventType.acknowledged),
        ),
    ];
  }
}
