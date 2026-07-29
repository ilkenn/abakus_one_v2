import 'kitchen_event.dart';
import 'kitchen_synchronization_state.dart';

/// Drives reconnect synchronization for one device — the cursor-based
/// replay path every device relies on for correctness, independent of
/// [KitchenEventSubscriber]'s best-effort live stream.
abstract interface class KitchenSynchronizationService {
  /// Every [KitchenEvent] with `sequence > cursor.lastProcessedSequence`
  /// for [branchId], oldest first, plus the resulting
  /// [KitchenSynchronizationState] once the device's cursor has been
  /// advanced past them. Ordered per-order by construction (events are
  /// returned in strict branch-wide sequence order, and every event for
  /// one order is itself sequenced), and idempotent — resyncing from the
  /// same cursor twice without an intervening successful sync replays the
  /// same batch rather than skipping or duplicating anything.
  Future<
      ({
        List<KitchenEvent> events,
        KitchenSynchronizationState state,
      })> synchronize({
    required String deviceId,
    required String branchId,
  });

  /// Computes [KitchenSynchronizationState] without advancing the
  /// device's cursor — for a status indicator that doesn't want to
  /// consume the pending replay batch.
  Future<KitchenSynchronizationState> currentState({
    required String deviceId,
    required String branchId,
  });
}
