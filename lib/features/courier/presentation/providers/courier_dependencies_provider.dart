import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/clock_provider.dart';
import '../../application/identity/courier_compensation_profile_id_generator.dart';
import '../../application/identity/courier_device_id_generator.dart';
import '../../application/identity/courier_device_session_id_generator.dart';
import '../../application/identity/courier_earnings_adjustment_id_generator.dart';
import '../../application/identity/courier_earnings_payment_id_generator.dart';
import '../../application/identity/courier_event_id_generator.dart';
import '../../application/identity/courier_feedback_id_generator.dart';
import '../../application/identity/courier_id_generator.dart';
import '../../application/identity/courier_location_snapshot_id_generator.dart';
import '../../application/identity/courier_shift_id_generator.dart';
import '../../application/identity/courier_shift_schedule_id_generator.dart';
import '../../application/identity/customer_contact_action_id_generator.dart';
import '../../application/identity/delivery_assignment_attempt_id_generator.dart';
import '../../application/identity/delivery_assignment_id_generator.dart';
import '../../application/identity/delivery_earnings_id_generator.dart';
import '../../application/identity/delivery_failure_id_generator.dart';
import '../../application/identity/delivery_id_generator.dart';
import '../../application/identity/delivery_proof_id_generator.dart';
import '../../application/identity/delivery_route_snapshot_id_generator.dart';
import '../../application/identity/geofence_override_id_generator.dart';
import '../../application/identity/pending_courier_command_id_generator.dart';
import '../../application/identity/shift_hourly_earnings_id_generator.dart';
import '../../application/services/in_memory_courier_connection_monitor.dart';
import '../../application/services/in_memory_courier_synchronization_service.dart';
import '../../data/courier_availability_repository.dart';
import '../../data/courier_compensation_profile_repository.dart';
import '../../data/courier_device_repository.dart';
import '../../data/courier_device_session_repository.dart';
import '../../data/courier_earnings_adjustment_repository.dart';
import '../../data/courier_earnings_payment_repository.dart';
import '../../data/courier_event_cursor_repository.dart';
import '../../data/courier_event_repository.dart';
import '../../data/courier_feedback_repository.dart';
import '../../data/courier_location_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/courier_operational_profile_repository.dart';
import '../../data/courier_repository.dart';
import '../../data/courier_shift_repository.dart';
import '../../data/courier_shift_schedule_repository.dart';
import '../../data/customer_contact_action_repository.dart';
import '../../data/delivery_assignment_attempt_repository.dart';
import '../../data/delivery_assignment_repository.dart';
import '../../data/delivery_earnings_repository.dart';
import '../../data/delivery_failure_repository.dart';
import '../../data/delivery_proof_repository.dart';
import '../../data/delivery_repository.dart';
import '../../data/delivery_tracking_repository.dart';
import '../../data/geofence_override_repository.dart';
import '../../data/in_memory_courier_event_bus.dart';
import '../../data/pending_courier_command_repository.dart';
import '../../data/shift_hourly_earnings_repository.dart';
import '../../domain/events/courier_connection_monitor.dart';
import '../../domain/events/courier_event_publisher.dart';
import '../../domain/events/courier_event_subscriber.dart';
import '../../domain/events/courier_synchronization_service.dart';

/// Every Phase 5 courier-operations repository/id-generator/service
/// currently in use — all in-memory today, no real-time backend exists
/// yet (`docs/decisions.md` ADR-017). Bundled in one file, mirroring
/// `kds_dependencies_provider.dart`'s own precedent (Phase 4) for the
/// same reason: this feature's screens each depend on several of these
/// at once. Deliberately **not** importing anything from
/// `pos/presentation/providers/*` — courier and KDS dependency graphs
/// stay parallel, never sharing a provider file (see this feature's own
/// "do not couple courier domain objects to KDS-specific contracts"
/// rule, extended here to the DI layer).
final courierRepositoryProvider = Provider<CourierRepository>((ref) {
  return InMemoryCourierRepository();
});

final courierOperationalProfileRepositoryProvider =
    Provider<CourierOperationalProfileRepository>((ref) {
  return InMemoryCourierOperationalProfileRepository();
});

final courierShiftRepositoryProvider = Provider<CourierShiftRepository>((ref) {
  return InMemoryCourierShiftRepository();
});

final courierAvailabilityRepositoryProvider =
    Provider<CourierAvailabilityRepository>((ref) {
  return InMemoryCourierAvailabilityRepository();
});

final deliveryRepositoryProvider = Provider<DeliveryRepository>((ref) {
  return InMemoryDeliveryRepository();
});

final deliveryAssignmentRepositoryProvider =
    Provider<DeliveryAssignmentRepository>((ref) {
  return InMemoryDeliveryAssignmentRepository();
});

final deliveryAssignmentAttemptRepositoryProvider =
    Provider<DeliveryAssignmentAttemptRepository>((ref) {
  return InMemoryDeliveryAssignmentAttemptRepository();
});

final deliveryFailureRepositoryProvider =
    Provider<DeliveryFailureRepository>((ref) {
  return InMemoryDeliveryFailureRepository();
});

final deliveryProofRepositoryProvider =
    Provider<DeliveryProofRepository>((ref) {
  return InMemoryDeliveryProofRepository();
});

final deliveryTrackingRepositoryProvider =
    Provider<DeliveryTrackingRepository>((ref) {
  return InMemoryDeliveryTrackingRepository();
});

final courierFeedbackRepositoryProvider =
    Provider<CourierFeedbackRepository>((ref) {
  return InMemoryCourierFeedbackRepository();
});

final courierDeviceRepositoryProvider =
    Provider<CourierDeviceRepository>((ref) {
  return InMemoryCourierDeviceRepository();
});

final courierDeviceSessionRepositoryProvider =
    Provider<CourierDeviceSessionRepository>((ref) {
  return InMemoryCourierDeviceSessionRepository();
});

final courierLocationRepositoryProvider =
    Provider<CourierLocationRepository>((ref) {
  return InMemoryCourierLocationRepository();
});

final geofenceOverrideRepositoryProvider =
    Provider<GeofenceOverrideRepository>((ref) {
  return InMemoryGeofenceOverrideRepository();
});

final customerContactActionRepositoryProvider =
    Provider<CustomerContactActionRepository>((ref) {
  return InMemoryCustomerContactActionRepository();
});

final courierEventRepositoryProvider = Provider<CourierEventRepository>((ref) {
  return InMemoryCourierEventRepository();
});

final courierEventCursorRepositoryProvider =
    Provider<CourierEventCursorRepository>((ref) {
  return InMemoryCourierEventCursorRepository();
});

final courierOperationalAuditEntryRepositoryProvider =
    Provider<CourierOperationalAuditEntryRepository>((ref) {
  return InMemoryCourierOperationalAuditEntryRepository();
});

final pendingCourierCommandRepositoryProvider =
    Provider<PendingCourierCommandRepository>((ref) {
  return InMemoryPendingCourierCommandRepository();
});

final courierEventBusProvider = Provider<InMemoryCourierEventBus>((ref) {
  return InMemoryCourierEventBus();
});

final courierEventPublisherProvider = Provider<CourierEventPublisher>((ref) {
  return ref.watch(courierEventBusProvider);
});

final courierEventSubscriberProvider = Provider<CourierEventSubscriber>((ref) {
  return ref.watch(courierEventBusProvider);
});

final courierSynchronizationServiceProvider =
    Provider<CourierSynchronizationService>((ref) {
  return InMemoryCourierSynchronizationService(
    clock: ref.watch(clockProvider),
    eventRepository: ref.watch(courierEventRepositoryProvider),
    cursorRepository: ref.watch(courierEventCursorRepositoryProvider),
  );
});

final courierConnectionMonitorProvider =
    Provider<CourierConnectionMonitor>((ref) {
  return InMemoryCourierConnectionMonitor(
    sessionRepository: ref.watch(courierDeviceSessionRepositoryProvider),
    deviceRepository: ref.watch(courierDeviceRepositoryProvider),
    courierRepository: ref.watch(courierRepositoryProvider),
  );
});

final courierIdGeneratorProvider = Provider<CourierIdGenerator>((ref) {
  return SequentialCourierIdGenerator();
});

final courierShiftIdGeneratorProvider =
    Provider<CourierShiftIdGenerator>((ref) {
  return SequentialCourierShiftIdGenerator();
});

final deliveryIdGeneratorProvider = Provider<DeliveryIdGenerator>((ref) {
  return SequentialDeliveryIdGenerator();
});

final deliveryAssignmentIdGeneratorProvider =
    Provider<DeliveryAssignmentIdGenerator>((ref) {
  return SequentialDeliveryAssignmentIdGenerator();
});

final deliveryAssignmentAttemptIdGeneratorProvider =
    Provider<DeliveryAssignmentAttemptIdGenerator>((ref) {
  return SequentialDeliveryAssignmentAttemptIdGenerator();
});

final deliveryFailureIdGeneratorProvider =
    Provider<DeliveryFailureIdGenerator>((ref) {
  return SequentialDeliveryFailureIdGenerator();
});

final deliveryProofIdGeneratorProvider =
    Provider<DeliveryProofIdGenerator>((ref) {
  return SequentialDeliveryProofIdGenerator();
});

final deliveryRouteSnapshotIdGeneratorProvider =
    Provider<DeliveryRouteSnapshotIdGenerator>((ref) {
  return SequentialDeliveryRouteSnapshotIdGenerator();
});

final courierFeedbackIdGeneratorProvider =
    Provider<CourierFeedbackIdGenerator>((ref) {
  return SequentialCourierFeedbackIdGenerator();
});

final courierDeviceIdGeneratorProvider =
    Provider<CourierDeviceIdGenerator>((ref) {
  return SequentialCourierDeviceIdGenerator();
});

final courierDeviceSessionIdGeneratorProvider =
    Provider<CourierDeviceSessionIdGenerator>((ref) {
  return SequentialCourierDeviceSessionIdGenerator();
});

final courierLocationSnapshotIdGeneratorProvider =
    Provider<CourierLocationSnapshotIdGenerator>((ref) {
  return SequentialCourierLocationSnapshotIdGenerator();
});

final geofenceOverrideIdGeneratorProvider =
    Provider<GeofenceOverrideIdGenerator>((ref) {
  return SequentialGeofenceOverrideIdGenerator();
});

final customerContactActionIdGeneratorProvider =
    Provider<CustomerContactActionIdGenerator>((ref) {
  return SequentialCustomerContactActionIdGenerator();
});

final courierEventIdGeneratorProvider =
    Provider<CourierEventIdGenerator>((ref) {
  return SequentialCourierEventIdGenerator();
});

final pendingCourierCommandIdGeneratorProvider =
    Provider<PendingCourierCommandIdGenerator>((ref) {
  return SequentialPendingCourierCommandIdGenerator();
});

/// Sprint 5A — Courier Compensation & Earnings. Same bundling convention
/// as everything above (`docs/decisions.md` ADR-018).
final courierCompensationProfileRepositoryProvider =
    Provider<CourierCompensationProfileRepository>((ref) {
  return InMemoryCourierCompensationProfileRepository();
});

final courierShiftScheduleRepositoryProvider =
    Provider<CourierShiftScheduleRepository>((ref) {
  return InMemoryCourierShiftScheduleRepository();
});

final deliveryEarningsRepositoryProvider =
    Provider<DeliveryEarningsRepository>((ref) {
  return InMemoryDeliveryEarningsRepository();
});

final shiftHourlyEarningsRepositoryProvider =
    Provider<ShiftHourlyEarningsRepository>((ref) {
  return InMemoryShiftHourlyEarningsRepository();
});

final courierEarningsAdjustmentRepositoryProvider =
    Provider<CourierEarningsAdjustmentRepository>((ref) {
  return InMemoryCourierEarningsAdjustmentRepository();
});

final courierEarningsPaymentRepositoryProvider =
    Provider<CourierEarningsPaymentRepository>((ref) {
  return InMemoryCourierEarningsPaymentRepository();
});

final courierCompensationProfileIdGeneratorProvider =
    Provider<CourierCompensationProfileIdGenerator>((ref) {
  return SequentialCourierCompensationProfileIdGenerator();
});

final courierShiftScheduleIdGeneratorProvider =
    Provider<CourierShiftScheduleIdGenerator>((ref) {
  return SequentialCourierShiftScheduleIdGenerator();
});

final deliveryEarningsIdGeneratorProvider =
    Provider<DeliveryEarningsIdGenerator>((ref) {
  return SequentialDeliveryEarningsIdGenerator();
});

final shiftHourlyEarningsIdGeneratorProvider =
    Provider<ShiftHourlyEarningsIdGenerator>((ref) {
  return SequentialShiftHourlyEarningsIdGenerator();
});

final courierEarningsAdjustmentIdGeneratorProvider =
    Provider<CourierEarningsAdjustmentIdGenerator>((ref) {
  return SequentialCourierEarningsAdjustmentIdGenerator();
});

final courierEarningsPaymentIdGeneratorProvider =
    Provider<CourierEarningsPaymentIdGenerator>((ref) {
  return SequentialCourierEarningsPaymentIdGenerator();
});
