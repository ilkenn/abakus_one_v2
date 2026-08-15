import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:geolocator/geolocator.dart' as geo;

import '../../../core/fraud/domain/fraud_evidence.dart';
import '../../../core/fraud/domain/mock_location_status.dart';

/// Faz P.2.1.2 (map-first UX) — one-shot device location for centering
/// the map-first address picker's initial camera position. Mirrors
/// `features/courier/data/geolocator_location_permission_gateway.dart`'s
/// own translation discipline: raw `geo.*` types never cross this
/// boundary, and every failure mode (permission denied, location
/// services disabled, any platform error) resolves to `null` rather than
/// throwing — this screen must never block address creation just
/// because location access isn't available (§5).
///
/// FRAUD-F.1 adds [captureLocationEvidence] — a **separate** one-shot
/// capture for fraud-evidence purposes, deliberately distinct from
/// [currentPosition] (which only ever centers the map camera and is never
/// sent to the server as evidence). Neither method is ever called
/// repeatedly, in the background, or on a timer — every call is a single,
/// explicit, foreground read.
abstract interface class AddressLocationGateway {
  /// `null` if permission is denied/unavailable/undeterminable for any
  /// reason — never throws.
  Future<({double latitude, double longitude})?> currentPosition();

  /// `true` only when permission was permanently denied (the platform
  /// will never show the prompt again) — used to decide whether to show
  /// the "ayarlardan açabilirsiniz" hint versus staying silent.
  Future<bool> isPermissionPermanentlyDenied();

  /// Exactly one foreground location read attempt for fraud-evidence
  /// purposes — FRAUD-F.1. Never repeated, never background, never
  /// continuous, never a route/history collection. Always returns a
  /// result, never throws: success produces an
  /// [DeviceLocationCaptureResult.available] result carrying real
  /// coordinates/accuracy/mock-status/permission/precision evidence;
  /// any failure (permission denied, service disabled, timeout, any
  /// platform error) produces [DeviceLocationCaptureResult.unavailable]
  /// with a reason — coordinates are never fabricated.
  Future<DeviceLocationCaptureResult> captureLocationEvidence();
}

/// Why [AddressLocationGateway.captureLocationEvidence] produced no usable
/// evidence — FRAUD-F.1. Internal diagnostic only, never shown to the
/// customer as an error (the address save proceeds regardless).
enum DeviceLocationUnavailableReason {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  error,
}

/// The outcome of one [AddressLocationGateway.captureLocationEvidence]
/// attempt — FRAUD-F.1. Exactly one of [evidence] or [unavailableReason]
/// is non-null.
class DeviceLocationCaptureResult {
  const DeviceLocationCaptureResult.available(ClientLocationEvidence value)
      : evidence = value,
        unavailableReason = null;

  const DeviceLocationCaptureResult.unavailable(
    DeviceLocationUnavailableReason reason,
  )   : evidence = null,
        unavailableReason = reason;

  final ClientLocationEvidence? evidence;
  final DeviceLocationUnavailableReason? unavailableReason;

  bool get isAvailable => evidence != null;
}

class GeolocatorAddressLocationGateway implements AddressLocationGateway {
  const GeolocatorAddressLocationGateway({
    this.captureTimeout = const Duration(seconds: 5),
  });

  /// Bounds how long [captureLocationEvidence] will wait for a GPS fix —
  /// FRAUD-F.1 §8's "GPS timeout/error: address can still save." Never
  /// applied to [currentPosition] (unchanged, pre-existing behavior).
  final Duration captureTimeout;

  @override
  Future<({double latitude, double longitude})?> currentPosition() async {
    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        return null;
      }
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      final position = await geo.Geolocator.getCurrentPosition();
      return (latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isPermissionPermanentlyDenied() async {
    try {
      final permission = await geo.Geolocator.checkPermission();
      return permission == geo.LocationPermission.deniedForever;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DeviceLocationCaptureResult> captureLocationEvidence() async {
    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      final reason =
          unavailableReasonFor(permission, serviceEnabled: serviceEnabled);
      if (reason != null) {
        return DeviceLocationCaptureResult.unavailable(reason);
      }

      final position = await geo.Geolocator.getCurrentPosition().timeout(
        captureTimeout,
      );
      geo.LocationAccuracyStatus accuracyStatus;
      try {
        accuracyStatus = await geo.Geolocator.getLocationAccuracy();
      } catch (_) {
        accuracyStatus = geo.LocationAccuracyStatus.unknown;
      }

      return DeviceLocationCaptureResult.available(
        clientLocationEvidenceFrom(
          position,
          accuracyStatus: accuracyStatus,
          isAndroid: Platform.isAndroid,
        ),
      );
    } catch (_) {
      // Covers GPS timeout, plugin/platform errors, and any other
      // unexpected failure — never surfaced to the customer as a raw
      // exception (§8).
      return const DeviceLocationCaptureResult.unavailable(
        DeviceLocationUnavailableReason.error,
      );
    }
  }
}

/// Pure decision logic (no plugin I/O) — FRAUD-F.1, independently
/// unit-testable without mocking the geolocator platform channel. `null`
/// means "proceed to capture," matching
/// [GeolocatorAddressLocationGateway.captureLocationEvidence]'s own
/// control flow exactly.
@visibleForTesting
DeviceLocationUnavailableReason? unavailableReasonFor(
  geo.LocationPermission permission, {
  required bool serviceEnabled,
}) {
  if (permission == geo.LocationPermission.deniedForever) {
    return DeviceLocationUnavailableReason.permissionDeniedForever;
  }
  if (permission == geo.LocationPermission.denied) {
    return DeviceLocationUnavailableReason.permissionDenied;
  }
  if (!serviceEnabled) {
    return DeviceLocationUnavailableReason.serviceDisabled;
  }
  return null;
}

/// Pure mapping (no plugin I/O) — FRAUD-F.1. `isAndroid` is an explicit
/// parameter (rather than reading `Platform.isAndroid` internally) so
/// this function is testable with plain data, no `dart:io`/plugin mocking
/// required.
@visibleForTesting
MockLocationStatus mockLocationStatusFor(
  geo.Position position, {
  required bool isAndroid,
}) {
  // iOS exposes no mock-location signal at all — an honest, permanent
  // platform gap, never a false `notDetected` (mirrors
  // `CourierLocationSnapshot.isMocked`'s own documented iOS gap).
  if (!isAndroid) return MockLocationStatus.unsupported;
  return position.isMocked
      ? MockLocationStatus.detected
      : MockLocationStatus.notDetected;
}

@visibleForTesting
String precisionStateFor(geo.LocationAccuracyStatus status) {
  switch (status) {
    case geo.LocationAccuracyStatus.precise:
      return 'precise';
    case geo.LocationAccuracyStatus.reduced:
      return 'reduced';
    case geo.LocationAccuracyStatus.unknown:
      return 'unknown';
  }
}

@visibleForTesting
ClientLocationEvidence clientLocationEvidenceFrom(
  geo.Position position, {
  required geo.LocationAccuracyStatus accuracyStatus,
  required bool isAndroid,
}) {
  return ClientLocationEvidence(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy,
    clientCapturedAt: position.timestamp,
    mockLocationStatus: mockLocationStatusFor(position, isAndroid: isAndroid),
    permissionState: 'granted',
    precisionState: precisionStateFor(accuracyStatus),
  );
}
