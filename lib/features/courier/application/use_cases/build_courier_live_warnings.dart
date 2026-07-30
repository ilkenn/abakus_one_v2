import '../../../../core/utils/clock.dart';
import '../../data/courier_fraud_signal_repository.dart';
import '../../data/courier_location_availability_repository.dart';
import '../../data/courier_repository.dart';
import '../../domain/fraud/courier_fraud_signal_type.dart';
import '../../domain/location/location_unavailable_reason.dart';
import '../../domain/location/movement_state.dart';
import '../../domain/warnings/courier_live_warning.dart';
import '../../domain/warnings/courier_live_warning_type.dart';
import 'build_courier_live_status.dart';

/// Aggregates every currently-active [CourierLiveWarning] for a branch —
/// Sprint 5C Part 9. A read-model builder only — see
/// [CourierLiveWarningType]'s own doc comment for why this introduces no
/// new detection logic, only surfaces existing Sprint 5B/5C signals.
class BuildCourierLiveWarnings {
  const BuildCourierLiveWarnings({
    required Clock clock,
    required CourierRepository courierRepository,
    required BuildCourierLiveStatus buildCourierLiveStatus,
    required CourierLocationAvailabilityRepository
        locationAvailabilityRepository,
    required CourierFraudSignalRepository fraudSignalRepository,
    this.noUpdateThreshold = const Duration(minutes: 5),
    this.longInactivityThreshold = const Duration(minutes: 15),
    this.recentSignalWindow = const Duration(hours: 1),
    this.operationalRiskSignalCount = 3,
  })  : _clock = clock,
        _courierRepository = courierRepository,
        _buildCourierLiveStatus = buildCourierLiveStatus,
        _locationAvailabilityRepository = locationAvailabilityRepository,
        _fraudSignalRepository = fraudSignalRepository;

  final Clock _clock;
  final CourierRepository _courierRepository;
  final BuildCourierLiveStatus _buildCourierLiveStatus;
  final CourierLocationAvailabilityRepository _locationAvailabilityRepository;
  final CourierFraudSignalRepository _fraudSignalRepository;

  /// No location update within this window triggers [CourierLiveWarningType
  /// .noLocationUpdates] — adjustable, never hardcoded inline.
  final Duration noUpdateThreshold;

  /// Stationary for at least this long (approximated by the age of the
  /// last reading while `movementState == stationary` — no separate
  /// "stationary since" timestamp exists, an honest approximation, not a
  /// hidden assumption) triggers [CourierLiveWarningType.longInactivity].
  final Duration longInactivityThreshold;

  /// How far back a `CourierFraudSignal` still counts as "recent" for
  /// [CourierLiveWarningType.abnormalRoute]/`.operationalRisk`.
  final Duration recentSignalWindow;

  /// This many recent fraud signals (any type) trigger
  /// [CourierLiveWarningType.operationalRisk].
  final int operationalRiskSignalCount;

  static const _abnormalRouteTypes = {
    CourierFraudSignalType.gpsJump,
    CourierFraudSignalType.unrealisticTravelDistance,
  };

  Future<List<CourierLiveWarning>> call({required String branchId}) async {
    final couriers = await _courierRepository.findByBranchId(branchId);
    final now = _clock.now();
    final warnings = <CourierLiveWarning>[];

    for (final courier in couriers) {
      final status = await _buildCourierLiveStatus(
        courierId: courier.id,
        branchId: branchId,
      );

      if (!status.isOnline) {
        warnings.add(CourierLiveWarning(
          courierId: courier.id,
          branchId: branchId,
          type: CourierLiveWarningType.courierOffline,
          description: '${courier.displayName} çevrimdışı',
          detectedAt: now,
        ));
      }

      final locationAvailability = await _locationAvailabilityRepository
          .findLatestByCourierId(courier.id);
      final reason = locationAvailability?.reason;
      if (reason == LocationUnavailableReason.serviceDisabled ||
          reason == LocationUnavailableReason.permissionDenied ||
          reason == LocationUnavailableReason.permissionRestricted) {
        warnings.add(CourierLiveWarning(
          courierId: courier.id,
          branchId: branchId,
          type: CourierLiveWarningType.gpsDisabled,
          description: '${courier.displayName}: GPS kapalı (${reason!.name})',
          detectedAt: now,
        ));
      }

      final lastUpdate = status.lastLocationUpdateAt;
      if (lastUpdate == null ||
          now.difference(lastUpdate) > noUpdateThreshold) {
        warnings.add(CourierLiveWarning(
          courierId: courier.id,
          branchId: branchId,
          type: CourierLiveWarningType.noLocationUpdates,
          description: '${courier.displayName}: konum güncellemesi yok',
          detectedAt: now,
        ));
      }

      if (status.movementState == MovementState.stationary &&
          lastUpdate != null &&
          now.difference(lastUpdate) > longInactivityThreshold) {
        warnings.add(CourierLiveWarning(
          courierId: courier.id,
          branchId: branchId,
          type: CourierLiveWarningType.longInactivity,
          description: '${courier.displayName}: uzun süredir hareketsiz',
          detectedAt: now,
        ));
      }

      final fraudSignals =
          await _fraudSignalRepository.findByCourierId(courier.id);
      final recentSignals = fraudSignals
          .where((s) => now.difference(s.detectedAt) <= recentSignalWindow)
          .toList();

      if (recentSignals.any((s) => _abnormalRouteTypes.contains(s.type))) {
        warnings.add(CourierLiveWarning(
          courierId: courier.id,
          branchId: branchId,
          type: CourierLiveWarningType.abnormalRoute,
          description: '${courier.displayName}: olağandışı rota sapması',
          detectedAt: now,
        ));
      }

      if (recentSignals.length >= operationalRiskSignalCount) {
        warnings.add(CourierLiveWarning(
          courierId: courier.id,
          branchId: branchId,
          type: CourierLiveWarningType.operationalRisk,
          description:
              '${courier.displayName}: ${recentSignals.length} operasyonel sinyal',
          detectedAt: now,
        ));
      }
    }

    return warnings;
  }
}
