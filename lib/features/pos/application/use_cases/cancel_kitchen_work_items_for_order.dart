import '../../../orders/domain/models/order_id.dart';
import '../../domain/kds/kitchen_line_status.dart';
import '../../domain/kds/kitchen_work_item.dart';
import '../../data/kitchen_projection_repository.dart';
import 'transition_kitchen_work_item.dart';

/// Cancels every still-active [KitchenWorkItem] for [orderId] — "full
/// order cancellation" (Phase 4E). Reuses [TransitionKitchenWorkItem] per
/// item (each cancellation is independently authorized, revisioned, and
/// audited — this use case is only the fan-out, not a bespoke second
/// cancellation code path). Already-terminal items (already cancelled/
/// unavailable/ready) are skipped rather than erroring, so a retry or a
/// partially-prepared order's cancellation never fails outright.
class CancelKitchenWorkItemsForOrder {
  const CancelKitchenWorkItemsForOrder({
    required KitchenProjectionRepository projectionRepository,
    required TransitionKitchenWorkItem transitionKitchenWorkItem,
  })  : _projectionRepository = projectionRepository,
        _transitionKitchenWorkItem = transitionKitchenWorkItem;

  final KitchenProjectionRepository _projectionRepository;
  final TransitionKitchenWorkItem _transitionKitchenWorkItem;

  Future<List<KitchenWorkItem>> call({
    required OrderId orderId,
    required String reason,
    required String performedByStaffId,
    String? deviceId,
  }) async {
    final items = await _projectionRepository.findByOrderId(orderId);
    final cancelled = <KitchenWorkItem>[];

    for (final item in items) {
      if (!KitchenLineStatusTransitions.canTransition(
        item.status,
        KitchenLineStatus.cancelled,
      )) {
        continue;
      }
      final updated = await _transitionKitchenWorkItem(
        workItemId: item.id,
        to: KitchenLineStatus.cancelled,
        expectedRevision: item.revision,
        performedByStaffId: performedByStaffId,
        deviceId: deviceId,
        reason: reason,
      );
      cancelled.add(updated);
    }

    return cancelled;
  }
}
