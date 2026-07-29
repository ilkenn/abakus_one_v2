import '../../../../core/utils/clock.dart';
import '../../data/courier_availability_repository.dart';
import '../../data/courier_location_availability_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/availability/courier_availability_status.dart';
import '../../domain/location/courier_location_availability.dart';
import '../../domain/location/location_unavailable_reason.dart';
import 'set_courier_availability.dart';

/// Records a change in a courier's device-reported location availability
/// — called whenever the app detects permission revoked, service
/// disabled, background tracking blocked, or GPS signal lost (and again
/// when it recovers). System-triggered, not manager/courier-gated (mirrors
/// `RecordCourierLocationSnapshot`'s own no-authorization precedent —
/// routine device telemetry, not a privileged action) but always audited.
///
/// **"If location becomes unavailable while no delivery is active, force
/// the courier into `temporarilyUnavailable` and prevent new
/// assignments"**: when [reason] is non-null (i.e. becoming unavailable)
/// and the courier has no active delivery, this calls the existing,
/// unmodified `SetCourierAvailability` directly. **Never calls
/// `TransitionCourierShift`** — "do not automatically complete or end the
/// shift when location is disabled" is satisfied structurally, by this
/// use case never depending on a shift-transition use case at all.
class ReportCourierLocationAvailability {
  const ReportCourierLocationAvailability({
    required Clock clock,
    required CourierLocationAvailabilityRepository availabilityRepository,
    required DeliveryRepository deliveryRepository,
    required CourierAvailabilityRepository courierAvailabilityRepository,
    required SetCourierAvailability setCourierAvailability,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _availabilityRepository = availabilityRepository,
        _deliveryRepository = deliveryRepository,
        _courierAvailabilityRepository = courierAvailabilityRepository,
        _setCourierAvailability = setCourierAvailability,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CourierLocationAvailabilityRepository _availabilityRepository;
  final DeliveryRepository _deliveryRepository;
  final CourierAvailabilityRepository _courierAvailabilityRepository;
  final SetCourierAvailability _setCourierAvailability;
  final CourierOperationalAuditEntryRepository _auditRepository;

  static const _defaultCapacity = 3;

  Future<CourierLocationAvailability> call({
    required String courierId,
    required String branchId,

    /// `null` means location became/remained available; non-null means
    /// unavailable, with the predefined reason.
    LocationUnavailableReason? reason,
    String? deviceId,
    String performedByStaffId = 'system',
  }) async {
    final now = _clock.now();
    final previous =
        await _availabilityRepository.findLatestByCourierId(courierId);
    final status = reason == null
        ? CourierLocationAvailabilityStatus.available
        : CourierLocationAvailabilityStatus.unavailable;

    final updated = CourierLocationAvailability(
      courierId: courierId,
      status: status,
      reason: reason,
      deviceId: deviceId,
      updatedAt: now,
      revision: (previous?.revision ?? 0) + 1,
    );
    await _availabilityRepository.save(updated);

    if (status == CourierLocationAvailabilityStatus.unavailable) {
      final activeDeliveries =
          await _deliveryRepository.findActiveByCourierId(courierId);
      if (activeDeliveries.isEmpty) {
        final currentAvailability =
            await _courierAvailabilityRepository.findByCourierId(courierId);
        await _setCourierAvailability(
          courierId: courierId,
          to: CourierAvailabilityStatus.temporarilyUnavailable,
          capacity: currentAvailability?.capacity ?? _defaultCapacity,
          performedByStaffId: performedByStaffId,
        );
      }
    }

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: 'locavail-$courierId-rev${updated.revision}',
      branchId: branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      deviceId: deviceId,
      type: CourierAuditEventType.locationAvailabilityChanged,
      description: status == CourierLocationAvailabilityStatus.available
          ? 'Location available'
          : 'Location unavailable: ${reason!.name}',
      previousStateName: previous?.status.name,
      newStateName: status.name,
      timestamp: now,
      correlationId: 'locavail-$courierId-rev${updated.revision}',
    ));

    return updated;
  }
}
