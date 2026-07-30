import '../domain/dispatch/courier_dispatch_queue_event.dart';

/// Append-only storage for [CourierDispatchQueueEvent] — Sprint 5C's FIFO
/// dispatch queue history.
abstract interface class CourierDispatchQueueEventRepository {
  Future<void> append(CourierDispatchQueueEvent event);
  Future<List<CourierDispatchQueueEvent>> findByBranchId(String branchId);
}

class InMemoryCourierDispatchQueueEventRepository
    implements CourierDispatchQueueEventRepository {
  final List<CourierDispatchQueueEvent> _events = [];

  @override
  Future<void> append(CourierDispatchQueueEvent event) async {
    _events.add(event);
  }

  @override
  Future<List<CourierDispatchQueueEvent>> findByBranchId(
      String branchId) async {
    return List.unmodifiable(_events.where((e) => e.branchId == branchId));
  }
}
