import '../../../../core/utils/clock.dart';
import '../../data/courier_dispatch_queue_event_repository.dart';
import '../../domain/dispatch/courier_dispatch_queue_builder.dart';
import '../../domain/dispatch/courier_dispatch_queue_snapshot.dart';

/// Assembles the current [CourierDispatchQueueSnapshot] for one branch —
/// Sprint 5C. A pure read-model builder over the existing, unmodified
/// `CourierDispatchQueueEventRepository`, no authorization gate (matches
/// `BuildCourierLiveStatus`'s own precedent).
class BuildCourierDispatchQueue {
  const BuildCourierDispatchQueue({
    required Clock clock,
    required CourierDispatchQueueEventRepository repository,
  })  : _clock = clock,
        _repository = repository;

  final Clock _clock;
  final CourierDispatchQueueEventRepository _repository;

  Future<CourierDispatchQueueSnapshot> call({required String branchId}) async {
    final events = await _repository.findByBranchId(branchId);
    return CourierDispatchQueueSnapshot(
      branchId: branchId,
      positions: CourierDispatchQueueBuilder.build(events),
      generatedAt: _clock.now(),
    );
  }
}
