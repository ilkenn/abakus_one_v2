import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/availability/courier_availability_status.dart';
import '../../domain/location/movement_state.dart';
import '../../domain/location/signal_quality.dart';

/// Shared Turkish display labels/colors for courier status enums — Sprint
/// 5C. Every new dispatch-center screen needs the same
/// `CourierAvailabilityStatus`/`MovementState`/`SignalQuality` labels;
/// centralizing them here avoids re-deriving the same Turkish copy in
/// every screen. Does not touch `ManagerLiveTrackingScreen`'s own
/// existing, already-tested private labels (Sprint 5B) — that file is
/// left unmodified, per "do not rewrite stable code."
abstract final class CourierStatusLabels {
  CourierStatusLabels._();

  static String availability(CourierAvailabilityStatus status) {
    switch (status) {
      case CourierAvailabilityStatus.online:
        return 'Çevrimiçi';
      case CourierAvailabilityStatus.offline:
        return 'Çevrimdışı';
      case CourierAvailabilityStatus.available:
        return 'Müsait';
      case CourierAvailabilityStatus.temporarilyUnavailable:
        return 'Geçici Olarak Müsait Değil';
      case CourierAvailabilityStatus.busy:
        return 'Teslimatta';
      case CourierAvailabilityStatus.paused:
        return 'Molada';
      case CourierAvailabilityStatus.suspended:
        return 'Askıya Alındı';
    }
  }

  static String movement(MovementState? state) {
    switch (state) {
      case null:
        return '—';
      case MovementState.stationary:
        return 'Duruyor';
      case MovementState.walking:
        return 'Yürüyor';
      case MovementState.vehicle:
        return 'Araçla Hareket Halinde';
      case MovementState.approachingTarget:
        return 'Hedefe Yaklaşıyor';
    }
  }

  static String signalQuality(SignalQuality? quality) {
    switch (quality) {
      case null:
        return 'Bilinmiyor';
      case SignalQuality.good:
        return 'İyi';
      case SignalQuality.fair:
        return 'Orta';
      case SignalQuality.poor:
        return 'Zayıf';
    }
  }

  static Color signalColor(SignalQuality? quality) {
    switch (quality) {
      case null:
        return AppColors.textSecondary;
      case SignalQuality.good:
        return AppColors.success;
      case SignalQuality.fair:
        return AppColors.warning;
      case SignalQuality.poor:
        return AppColors.error;
    }
  }

  /// Marker/status-dot color by availability — green when actively
  /// dispatchable, amber when on a delivery, red/grey otherwise.
  static Color availabilityColor(CourierAvailabilityStatus status) {
    switch (status) {
      case CourierAvailabilityStatus.available:
      case CourierAvailabilityStatus.online:
        return AppColors.success;
      case CourierAvailabilityStatus.busy:
        return AppColors.warning;
      case CourierAvailabilityStatus.paused:
      case CourierAvailabilityStatus.temporarilyUnavailable:
        return AppColors.textSecondary;
      case CourierAvailabilityStatus.offline:
      case CourierAvailabilityStatus.suspended:
        return AppColors.error;
    }
  }
}
