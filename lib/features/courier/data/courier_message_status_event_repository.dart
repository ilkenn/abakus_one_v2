import '../domain/communication/courier_message_status_event.dart';

/// Append-only storage for [CourierMessageStatusEvent] — Sprint 5C.
abstract interface class CourierMessageStatusEventRepository {
  Future<void> append(CourierMessageStatusEvent event);
  Future<List<CourierMessageStatusEvent>> findByMessageId(String messageId);
}

class InMemoryCourierMessageStatusEventRepository
    implements CourierMessageStatusEventRepository {
  final List<CourierMessageStatusEvent> _events = [];

  @override
  Future<void> append(CourierMessageStatusEvent event) async {
    _events.add(event);
  }

  @override
  Future<List<CourierMessageStatusEvent>> findByMessageId(
      String messageId) async {
    return List.unmodifiable(_events.where((e) => e.messageId == messageId));
  }
}
