import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_compensation_profile_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_earnings_repository.dart';
import '../../data/delivery_repository.dart';
import '../../data/delivery_tracking_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/compensation/delivery_earnings.dart';
import '../../domain/delivery/delivery_status.dart';
import '../identity/delivery_earnings_id_generator.dart';

/// Computes and stores the one-time [DeliveryEarnings] record for a
/// completed [Delivery] — "package earnings are added only after
/// successful delivery completion." **Idempotent**: a second call for a
/// delivery that already has a [DeliveryEarnings] record returns it
/// unchanged rather than recomputing — earnings are locked the moment
/// they exist, with no update method anywhere to reopen them.
///
/// "Cancelled deliveries do not generate package earnings unless
/// manager-approved": [managerApprovedCancellation] (with
/// [approvalReason]) is the only way a `DeliveryStatus.cancelled` delivery
/// may still earn a package fee — gated by
/// [PosAuthorizedAction.approveCancelledDeliveryEarnings] rather than the
/// routine [PosAuthorizedAction.calculateCourierEarnings].
///
/// Distance is read from `DeliveryTrackingRepository`
/// (`DeliveryRouteSnapshot.distanceEstimateMeters`) — that type is
/// documented as non-authoritative/informational-only; it is reused here
/// for lack of any other distance source in this codebase (see
/// `docs/decisions.md` ADR-018's honest limitation note). No snapshot at
/// all means zero distance, never an error.
class CalculateDeliveryEarnings {
  const CalculateDeliveryEarnings({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required DeliveryEarningsIdGenerator idGenerator,
    required DeliveryRepository deliveryRepository,
    required DeliveryTrackingRepository trackingRepository,
    required CourierCompensationProfileRepository compensationProfileRepository,
    required DeliveryEarningsRepository earningsRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _deliveryRepository = deliveryRepository,
        _trackingRepository = trackingRepository,
        _compensationProfileRepository = compensationProfileRepository,
        _earningsRepository = earningsRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final DeliveryEarningsIdGenerator _idGenerator;
  final DeliveryRepository _deliveryRepository;
  final DeliveryTrackingRepository _trackingRepository;
  final CourierCompensationProfileRepository _compensationProfileRepository;
  final DeliveryEarningsRepository _earningsRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<DeliveryEarnings> call({
    required String deliveryId,
    bool managerApprovedCancellation = false,
    String? approvalReason,
    required String performedByStaffId,
  }) async {
    final existing = await _earningsRepository.findByDeliveryId(deliveryId);
    if (existing != null) return existing;

    final delivery = await _deliveryRepository.findById(deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: deliveryId,
      );
    }

    final isEligible = delivery.status == DeliveryStatus.delivered ||
        (delivery.status == DeliveryStatus.cancelled &&
            managerApprovedCancellation);
    if (!isEligible) {
      throw DeliveryNotEligibleForEarningsViolation(
        deliveryId: deliveryId,
        statusName: delivery.status.name,
      );
    }

    final courierId = delivery.courierId;
    if (courierId == null) {
      throw DeliveryNotEligibleForEarningsViolation(
        deliveryId: deliveryId,
        statusName: 'unassigned',
      );
    }

    final action = managerApprovedCancellation
        ? PosAuthorizedAction.approveCancelledDeliveryEarnings
        : PosAuthorizedAction.calculateCourierEarnings;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'deliveryId': deliveryId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final at = delivery.deliveredAt ?? now;
    final profile = await _compensationProfileRepository.findEffectiveAt(
      courierId: courierId,
      at: at,
    );
    if (profile == null) {
      throw NoEffectiveCompensationProfileViolation(
        courierId: courierId,
        at: at,
      );
    }

    final routeSnapshot =
        await _trackingRepository.findLatestByDeliveryId(deliveryId);
    final distanceMeters = (routeSnapshot?.distanceEstimateMeters ?? 0).round();
    final freeDistanceMeters = (profile.freeDistanceKm * 1000).round();
    final extraDistanceMeters = (distanceMeters - freeDistanceMeters) > 0
        ? distanceMeters - freeDistanceMeters
        : 0;

    final extraDistanceRate = profile.extraDistanceRatePerKm ??
        Money.zero(Currency.accountingCurrency);
    final extraDistanceEarnings =
        extraDistanceRate.scaledBy(extraDistanceMeters, 1000);
    final packageFee = profile.deliveryFeePerPackage ??
        Money.zero(Currency.accountingCurrency);
    final totalEarnings = packageFee + extraDistanceEarnings;

    final earnings = DeliveryEarnings(
      id: _idGenerator.nextEarningsId(),
      deliveryId: deliveryId,
      courierId: courierId,
      orderId: delivery.orderId,
      compensationProfileId: profile.id,
      compensationProfileVersion: profile.version,
      packageFee: packageFee,
      distanceKm: distanceMeters / 1000,
      freeDistanceKm: profile.freeDistanceKm,
      extraDistanceKm: extraDistanceMeters / 1000,
      extraDistanceEarnings: extraDistanceEarnings,
      totalEarnings: totalEarnings,
      wasManagerApprovedCancellation: managerApprovedCancellation,
      approvalReason: approvalReason,
      calculatedAt: now,
    );
    await _earningsRepository.append(earnings);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${earnings.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      orderId: delivery.orderId.value,
      deliveryId: deliveryId,
      type: CourierAuditEventType.deliveryEarningsCalculated,
      description: 'Delivery earnings calculated: ${totalEarnings.minorUnits} '
          'minor units',
      reason: approvalReason,
      timestamp: now,
      correlationId: earnings.id,
    ));

    return earnings;
  }
}
