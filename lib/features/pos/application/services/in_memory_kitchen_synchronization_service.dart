import '../../../../core/utils/clock.dart';
import '../../data/kitchen_event_cursor_repository.dart';
import '../../data/kitchen_event_repository.dart';
import '../../domain/kds/kitchen_event.dart';
import '../../domain/kds/kitchen_event_cursor.dart';
import '../../domain/kds/kitchen_synchronization_service.dart';
import '../../domain/kds/kitchen_synchronization_state.dart';

/// The only [KitchenSynchronizationService] implementation this phase —
/// backed by [KitchenEventRepository]/[KitchenEventCursorRepository],
/// both in-memory. Deterministic and ordered: [synchronize] always
/// returns events in ascending `sequence` order and advances the cursor
/// to the last one delivered, so calling it again immediately (before any
/// new event exists) returns an empty batch rather than redelivering —
/// idempotent by construction, not by a separate dedup check.
class InMemoryKitchenSynchronizationService
    implements KitchenSynchronizationService {
  InMemoryKitchenSynchronizationService({
    required Clock clock,
    required KitchenEventRepository eventRepository,
    required KitchenEventCursorRepository cursorRepository,
  })  : _clock = clock,
        _eventRepository = eventRepository,
        _cursorRepository = cursorRepository;

  final Clock _clock;
  final KitchenEventRepository _eventRepository;
  final KitchenEventCursorRepository _cursorRepository;

  @override
  Future<
      ({
        List<KitchenEvent> events,
        KitchenSynchronizationState state,
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
      await _cursorRepository.save(KitchenEventCursor(
        deviceId: deviceId,
        branchId: branchId,
        lastProcessedSequence: events.last.sequence,
        updatedAt: now,
      ));
    } else if (cursor == null) {
      await _cursorRepository.save(KitchenEventCursor(
        deviceId: deviceId,
        branchId: branchId,
        lastProcessedSequence: 0,
        updatedAt: now,
      ));
    }

    return (
      events: events,
      state: KitchenSynchronizationState(
        deviceId: deviceId,
        isSynchronized: true,
        lastSyncedAt: now,
        pendingEventCount: 0,
        isStale: false,
      ),
    );
  }

  @override
  Future<KitchenSynchronizationState> currentState({
    required String deviceId,
    required String branchId,
  }) async {
    final cursor = await _cursorRepository.findByDeviceId(deviceId);
    final afterSequence = cursor?.lastProcessedSequence ?? 0;
    final pending = await _eventRepository.findSince(
      branchId: branchId,
      afterSequence: afterSequence,
    );

    return KitchenSynchronizationState(
      deviceId: deviceId,
      isSynchronized: pending.isEmpty,
      lastSyncedAt: cursor?.updatedAt,
      pendingEventCount: pending.length,
      isStale: false,
    );
  }
}
