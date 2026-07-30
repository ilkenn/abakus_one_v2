import '../../../../core/utils/clock.dart';
import '../../data/courier_dispatch_queue_event_repository.dart';
import '../../domain/dispatch/courier_dispatch_queue_event.dart';
import '../identity/courier_dispatch_queue_event_id_generator.dart';

/// Records a courier entering/leaving the FIFO dispatch queue — Sprint 5C.
/// Injected as an optional collaborator into `SetCourierAvailability`,
/// `RespondToDeliveryAssignment`, and `CompleteDelivery` (mirrors the
/// Sprint 5B `CourierLocationAvailabilityGuard` optional-dependency
/// pattern exactly) so queue membership stays automatically in sync with
/// the same lifecycle transitions that already govern availability/
/// delivery state, without those use cases owning queue logic themselves.
class SyncCourierDispatchQueue {
  const SyncCourierDispatchQueue({
    required Clock clock,
    required CourierDispatchQueueEventIdGenerator idGenerator,
    required CourierDispatchQueueEventRepository repository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _repository = repository;

  final Clock _clock;
  final CourierDispatchQueueEventIdGenerator _idGenerator;
  final CourierDispatchQueueEventRepository _repository;

  Future<void> enter({
    required String courierId,
    required String branchId,
  }) async {
    await _repository.append(CourierDispatchQueueEvent(
      id: _idGenerator.nextEventId(),
      branchId: branchId,
      courierId: courierId,
      type: CourierDispatchQueueEventType.entered,
      occurredAt: _clock.now(),
    ));
  }

  Future<void> leave({
    required String courierId,
    required String branchId,
    required CourierDispatchQueueLeaveReason reason,
  }) async {
    await _repository.append(CourierDispatchQueueEvent(
      id: _idGenerator.nextEventId(),
      branchId: branchId,
      courierId: courierId,
      type: CourierDispatchQueueEventType.left,
      leaveReason: reason,
      occurredAt: _clock.now(),
    ));
  }
}
