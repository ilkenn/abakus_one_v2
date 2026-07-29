import '../domain/events/courier_event_cursor.dart';

/// Storage for [CourierEventCursor]s — one per device, mutable.
abstract interface class CourierEventCursorRepository {
  Future<void> save(CourierEventCursor cursor);
  Future<CourierEventCursor?> findByDeviceId(String deviceId);
}

class InMemoryCourierEventCursorRepository
    implements CourierEventCursorRepository {
  final Map<String, CourierEventCursor> _byDeviceId = {};

  @override
  Future<void> save(CourierEventCursor cursor) async =>
      _byDeviceId[cursor.deviceId] = cursor;

  @override
  Future<CourierEventCursor?> findByDeviceId(String deviceId) async =>
      _byDeviceId[deviceId];
}
