import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_location_availability_repository.dart';
import '../../data/location_emergency_override_repository.dart';
import '../../domain/location/courier_location_availability.dart';

/// The reusable check every state-changing courier-operational use case
/// threads through — "a courier must not be operationally usable without
/// location access during an active shift" (Sprint 5B REQUIRED
/// business-rule correction).
///
/// Allows the action when either: (a) the courier's latest
/// [CourierLocationAvailability] is
/// [CourierLocationAvailabilityStatus.available], or (b) a manager has
/// granted an active, non-expired `LocationEmergencyOverride` covering
/// this courier — either a delivery-specific one (`deliveryId` matches)
/// or a courier-wide one (`deliveryId == null` on the override, covering
/// every action). Otherwise throws [LocationUnavailableViolation].
///
/// Deliberately a small, standalone, reusable checker — not folded into
/// any single use case — so it can be threaded into
/// `TransitionCourierShift`/`SetCourierAvailability`/
/// `RespondToDeliveryAssignment`/`ConfirmPackagePickup`/
/// `TransitionDelivery`/`CompleteDelivery` as one optional constructor
/// dependency each, never restructuring their existing logic.
class CourierLocationAvailabilityGuard {
  const CourierLocationAvailabilityGuard({
    required Clock clock,
    required CourierLocationAvailabilityRepository availabilityRepository,
    required LocationEmergencyOverrideRepository overrideRepository,
  })  : _clock = clock,
        _availabilityRepository = availabilityRepository,
        _overrideRepository = overrideRepository;

  final Clock _clock;
  final CourierLocationAvailabilityRepository _availabilityRepository;
  final LocationEmergencyOverrideRepository _overrideRepository;

  Future<void> assertAvailable({
    required String courierId,
    String? deliveryId,
  }) async {
    final latest =
        await _availabilityRepository.findLatestByCourierId(courierId);
    if (latest == null || latest.isAvailable) return;

    final now = _clock.now();
    final overrides = await _overrideRepository.findByCourierId(courierId);
    final hasActiveOverride = overrides.any((o) =>
        o.isActiveAt(now) &&
        (o.deliveryId == null || o.deliveryId == deliveryId));
    if (hasActiveOverride) return;

    throw LocationUnavailableViolation(
      courierId: courierId,
      reasonName: latest.reason?.name,
    );
  }
}
