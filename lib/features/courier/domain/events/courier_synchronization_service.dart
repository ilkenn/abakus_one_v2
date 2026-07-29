import 'courier_event.dart';
import 'courier_synchronization_state.dart';

/// Drives reconnect synchronization for one courier device — mirrors
/// `KitchenSynchronizationService`'s cursor-based replay contract exactly,
/// as a deliberately separate type.
abstract interface class CourierSynchronizationService {
  Future<
      ({
        List<CourierEvent> events,
        CourierSynchronizationState state,
      })> synchronize({
    required String deviceId,
    required String branchId,
  });

  Future<CourierSynchronizationState> currentState({
    required String deviceId,
    required String branchId,
  });
}
