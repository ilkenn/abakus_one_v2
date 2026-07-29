import '../domain/kds/kitchen_event_cursor.dart';

/// Storage for [KitchenEventCursor]s — one per device, mutable (a cursor's
/// current position is what matters, not a revision history of it; the
/// append-only requirement in this phase applies to the events themselves,
/// not the cursor tracking how far a device has replayed them).
abstract interface class KitchenEventCursorRepository {
  Future<void> save(KitchenEventCursor cursor);

  Future<KitchenEventCursor?> findByDeviceId(String deviceId);
}

/// In-memory [KitchenEventCursorRepository] — the only implementation
/// this phase.
class InMemoryKitchenEventCursorRepository
    implements KitchenEventCursorRepository {
  final Map<String, KitchenEventCursor> _cursorsByDeviceId = {};

  @override
  Future<void> save(KitchenEventCursor cursor) async {
    _cursorsByDeviceId[cursor.deviceId] = cursor;
  }

  @override
  Future<KitchenEventCursor?> findByDeviceId(String deviceId) async {
    return _cursorsByDeviceId[deviceId];
  }
}
