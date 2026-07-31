import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clock_provider.dart';
import '../../application/identity/courier_fraud_signal_id_generator.dart';
import '../../application/identity/courier_location_audit_action_id_generator.dart';
import '../../application/identity/geofence_transition_event_id_generator.dart';
import '../../application/identity/location_emergency_override_id_generator.dart';
import '../../application/use_cases/build_courier_live_status.dart';
import '../../application/use_cases/build_courier_live_status_for_branch.dart';
import '../../application/use_cases/build_courier_live_warnings.dart';
import '../../application/use_cases/build_courier_operation_health.dart';
import '../../application/use_cases/build_courier_operation_timeline.dart';
import '../../application/use_cases/build_delivery_tracking_history.dart';
import '../../application/use_cases/courier_location_availability_guard.dart';
import '../../application/use_cases/detect_courier_fraud_signals.dart';
import '../../application/use_cases/detect_repeated_location_loss_signal.dart';
import '../../application/use_cases/record_courier_event.dart';
import '../../application/use_cases/sync_queued_courier_locations.dart';
import '../../data/courier_fraud_signal_repository.dart';
import '../../data/courier_location_availability_repository.dart';
import '../../data/geofence_transition_event_repository.dart';
import '../../data/location_emergency_override_repository.dart';
import '../../data/offline_location_queue_repository.dart';
import 'courier_core_dependencies_provider.dart';

/// Sprint 5B — real GPS/geofence/ETA/live-tracking/fraud-detection
/// dependencies, split out of `courier_dependencies_provider.dart`
/// (Sprint 5E Part 7, `docs/decisions.md` ADR-022). Depends on several
/// [courier_core_dependencies_provider.dart] providers (delivery/
/// location/courier/audit repositories) — imported explicitly rather
/// than re-declared.
final courierLocationAvailabilityRepositoryProvider =
    Provider<CourierLocationAvailabilityRepository>((ref) {
  return InMemoryCourierLocationAvailabilityRepository();
});

final locationEmergencyOverrideRepositoryProvider =
    Provider<LocationEmergencyOverrideRepository>((ref) {
  return InMemoryLocationEmergencyOverrideRepository();
});

final locationEmergencyOverrideIdGeneratorProvider =
    Provider<LocationEmergencyOverrideIdGenerator>((ref) {
  return SequentialLocationEmergencyOverrideIdGenerator();
});

final geofenceTransitionEventRepositoryProvider =
    Provider<GeofenceTransitionEventRepository>((ref) {
  return InMemoryGeofenceTransitionEventRepository();
});

final geofenceTransitionEventIdGeneratorProvider =
    Provider<GeofenceTransitionEventIdGenerator>((ref) {
  return SequentialGeofenceTransitionEventIdGenerator();
});

final courierLocationAvailabilityGuardProvider =
    Provider<CourierLocationAvailabilityGuard>((ref) {
  return CourierLocationAvailabilityGuard(
    clock: ref.watch(clockProvider),
    availabilityRepository:
        ref.watch(courierLocationAvailabilityRepositoryProvider),
    overrideRepository: ref.watch(locationEmergencyOverrideRepositoryProvider),
  );
});

final buildCourierLiveStatusProvider = Provider<BuildCourierLiveStatus>((ref) {
  return BuildCourierLiveStatus(
    clock: ref.watch(clockProvider),
    locationRepository: ref.watch(courierLocationRepositoryProvider),
    connectionMonitor: ref.watch(courierConnectionMonitorProvider),
    availabilityRepository: ref.watch(courierAvailabilityRepositoryProvider),
    locationAvailabilityRepository:
        ref.watch(courierLocationAvailabilityRepositoryProvider),
    deliveryRepository: ref.watch(deliveryRepositoryProvider),
  );
});

final buildCourierLiveStatusForBranchProvider =
    Provider<BuildCourierLiveStatusForBranch>((ref) {
  return BuildCourierLiveStatusForBranch(
    courierRepository: ref.watch(courierRepositoryProvider),
    buildCourierLiveStatus: ref.watch(buildCourierLiveStatusProvider),
  );
});

final offlineLocationQueueRepositoryProvider =
    Provider<OfflineLocationQueueRepository>((ref) {
  return InMemoryOfflineLocationQueueRepository();
});

final syncQueuedCourierLocationsProvider =
    Provider<SyncQueuedCourierLocations>((ref) {
  return SyncQueuedCourierLocations(
    clock: ref.watch(clockProvider),
    queueRepository: ref.watch(offlineLocationQueueRepositoryProvider),
    locationRepository: ref.watch(courierLocationRepositoryProvider),
    recordCourierEvent: RecordCourierEvent(
      idGenerator: ref.watch(courierEventIdGeneratorProvider),
      eventRepository: ref.watch(courierEventRepositoryProvider),
      eventPublisher: ref.watch(courierEventPublisherProvider),
    ),
  );
});

final courierFraudSignalRepositoryProvider =
    Provider<CourierFraudSignalRepository>((ref) {
  return InMemoryCourierFraudSignalRepository();
});

final courierFraudSignalIdGeneratorProvider =
    Provider<CourierFraudSignalIdGenerator>((ref) {
  return SequentialCourierFraudSignalIdGenerator();
});

final detectCourierFraudSignalsProvider =
    Provider<DetectCourierFraudSignals>((ref) {
  return DetectCourierFraudSignals(
    clock: ref.watch(clockProvider),
    idGenerator: ref.watch(courierFraudSignalIdGeneratorProvider),
    repository: ref.watch(courierFraudSignalRepositoryProvider),
    auditRepository: ref.watch(courierOperationalAuditEntryRepositoryProvider),
  );
});

final detectRepeatedLocationLossSignalProvider =
    Provider<DetectRepeatedLocationLossSignal>((ref) {
  return DetectRepeatedLocationLossSignal(
    clock: ref.watch(clockProvider),
    availabilityRepository:
        ref.watch(courierLocationAvailabilityRepositoryProvider),
    idGenerator: ref.watch(courierFraudSignalIdGeneratorProvider),
    repository: ref.watch(courierFraudSignalRepositoryProvider),
    auditRepository: ref.watch(courierOperationalAuditEntryRepositoryProvider),
  );
});

final buildCourierLiveWarningsProvider =
    Provider<BuildCourierLiveWarnings>((ref) {
  return BuildCourierLiveWarnings(
    clock: ref.watch(clockProvider),
    courierRepository: ref.watch(courierRepositoryProvider),
    buildCourierLiveStatus: ref.watch(buildCourierLiveStatusProvider),
    locationAvailabilityRepository:
        ref.watch(courierLocationAvailabilityRepositoryProvider),
    fraudSignalRepository: ref.watch(courierFraudSignalRepositoryProvider),
  );
});

final buildCourierOperationTimelineProvider =
    Provider<BuildCourierOperationTimeline>((ref) {
  return BuildCourierOperationTimeline(
    auditRepository: ref.watch(courierOperationalAuditEntryRepositoryProvider),
    courierRepository: ref.watch(courierRepositoryProvider),
  );
});

final buildCourierOperationHealthProvider =
    Provider<BuildCourierOperationHealth>((ref) {
  return BuildCourierOperationHealth(
    clock: ref.watch(clockProvider),
    deliveryRepository: ref.watch(deliveryRepositoryProvider),
    buildCourierLiveWarnings: ref.watch(buildCourierLiveWarningsProvider),
  );
});

final buildDeliveryTrackingHistoryProvider =
    Provider<BuildDeliveryTrackingHistory>((ref) {
  return BuildDeliveryTrackingHistory(
    locationRepository: ref.watch(courierLocationRepositoryProvider),
    auditRepository: ref.watch(courierOperationalAuditEntryRepositoryProvider),
  );
});

/// Sprint 5B Part 11. `StartCourierLocationTracking`/
/// `StopCourierLocationTracking`/`ResetCourierLocationHistory` are not
/// bundled here as full use-case providers — like every other authorized
/// courier-operations use case in this feature (see
/// `CourierDispatchBoardScreen`'s `_reviewShift`/`_manuallyAssign`), they
/// need a `PosAuthorizationPolicy` supplied by whichever screen
/// constructs them, never resolved from this file (this file deliberately
/// never imports `pos/presentation/providers/*`). This id generator is
/// still bundled since it has no such external dependency.
final courierLocationAuditActionIdGeneratorProvider =
    Provider<CourierLocationAuditActionIdGenerator>((ref) {
  return SequentialCourierLocationAuditActionIdGenerator();
});
