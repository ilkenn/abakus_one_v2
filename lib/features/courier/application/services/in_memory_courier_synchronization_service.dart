import '../../../../core/utils/clock.dart';
import '../../data/courier_event_cursor_repository.dart';
import '../../data/courier_event_repository.dart';
import '../../domain/events/courier_event.dart';
import '../../domain/events/courier_event_cursor.dart';
import '../../domain/events/courier_synchronization_service.dart';
import '../../domain/events/courier_synchronization_state.dart';

/// The only [CourierSynchronizationService] implementation this phase —
/// mirrors `InMemoryKitchenSynchronizationService`'s shape and reasoning
/// exactly, as a deliberately separate type.
class InMemoryCourierSynchronizationService
    implements CourierSynchronizationService {
  InMemoryCourierSynchronizationService({
    required Clock clock,
    required CourierEventRepository eventRepository,
    required CourierEventCursorRepository cursorRepository,
  })  : _clock = clock,
        _eventRepository = eventRepository,
        _cursorRepository = cursorRepository;

  final Clock _clock;
  final CourierEventRepository _eventRepository;
  final CourierEventCursorRepository _cursorRepository;

  @override
  Future<
      ({
        List<CourierEvent> events,
        CourierSynchronizationState state,
      })> synchronize({
    required String deviceId,
    required String branchId,
  }) async {
    final cursor = await _cursorRepository.findByDeviceId(deviceId);
    final afterSequence = cursor?.lastProcessedSequence ?? 0;
    final events = await _eventRepository.findSince(
      branchId: branchId,
      afterSequence: afterSequence,
    );

    final now = _clock.now();
    if (events.isNotEmpty) {
      await _cursorRepository.save(CourierEventCursor(
        deviceId: deviceId,
        branchId: branchId,
        lastProcessedSequence: events.last.sequence,
        updatedAt: now,
      ));
    } else if (cursor == null) {
      await _cursorRepository.save(CourierEventCursor(
        deviceId: deviceId,
        branchId: branchId,
        lastProcessedSequence: 0,
        updatedAt: now,
      ));
    }

    return (
      events: events,
      state: CourierSynchronizationState(
        deviceId: deviceId,
        isSynchronized: true,
        lastSyncedAt: now,
        pendingEventCount: 0,
        isStale: false,
      ),
    );
  }

  @override
  Future<CourierSynchronizationState> currentState({
    required String deviceId,
    required String branchId,
  }) async {
    final cursor = await _cursorRepository.findByDeviceId(deviceId);
    final afterSequence = cursor?.lastProcessedSequence ?? 0;
    final pending = await _eventRepository.findSince(
      branchId: branchId,
      afterSequence: afterSequence,
    );

    return CourierSynchronizationState(
      deviceId: deviceId,
      isSynchronized: pending.isEmpty,
      lastSyncedAt: cursor?.updatedAt,
      pendingEventCount: pending.length,
      isStale: false,
    );
  }
}
