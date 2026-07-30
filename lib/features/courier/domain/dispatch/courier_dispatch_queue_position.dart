/// One courier's current position in the branch's FIFO dispatch queue —
/// Sprint 5C. Computed fresh by `CourierDispatchQueueBuilder`, never
/// persisted itself.
class CourierDispatchQueuePosition {
  const CourierDispatchQueuePosition({
    required this.courierId,
    required this.position,
    required this.enteredQueueAt,
  });

  final String courierId;

  /// 1-based — position 1 is "next recommendation."
  final int position;
  final DateTime enteredQueueAt;
}
