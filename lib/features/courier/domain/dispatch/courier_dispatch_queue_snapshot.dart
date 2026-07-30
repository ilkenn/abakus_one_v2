import 'courier_dispatch_queue_position.dart';

/// The manager-facing FIFO queue view for one branch — Sprint 5C. "Manager
/// must see: current queue, next recommendation" — [nextRecommendation]
/// is simply [positions]' head (position 1, earliest `enteredQueueAt`).
class CourierDispatchQueueSnapshot {
  const CourierDispatchQueueSnapshot({
    required this.branchId,
    required this.positions,
    required this.generatedAt,
  });

  final String branchId;

  /// Ordered, position 1 first.
  final List<CourierDispatchQueuePosition> positions;
  final DateTime generatedAt;

  CourierDispatchQueuePosition? get nextRecommendation =>
      positions.isEmpty ? null : positions.first;
}
