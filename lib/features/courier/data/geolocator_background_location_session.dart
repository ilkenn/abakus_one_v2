import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../domain/location/background_location_session.dart';

/// Real, device-backed [BackgroundLocationSession] — Sprint 5B Part 1.
///
/// Deliberately narrow, matching the existing interface contract exactly:
/// this session's only job is to keep the platform's *sustained
/// background execution capability* alive (Android foreground service via
/// `ForegroundNotificationConfig`; iOS background location mode via
/// `AppleSettings.allowBackgroundLocationUpdates`) — it does **not** read
/// or record positions itself. Actual location data continues to flow
/// through `CourierLocationProvider.watch()`, subscribed to separately;
/// this session only ensures that subscription keeps receiving updates
/// while the app is backgrounded. Holds its own internal stream
/// subscription (positions discarded) purely to hold the platform
/// capability open for the subscription's lifetime.
class GeolocatorBackgroundLocationSession implements BackgroundLocationSession {
  StreamSubscription<geo.Position>? _subscription;

  static geo.LocationSettings _backgroundSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return geo.AndroidSettings(
        accuracy: geo.LocationAccuracy.medium,
        distanceFilter: 0,
        foregroundNotificationConfig: const geo.ForegroundNotificationConfig(
          notificationTitle: 'Abaküs Kurye',
          notificationText: 'Aktif teslimat sırasında konumunuz paylaşılıyor.',
          notificationChannelName: 'Konum Takibi',
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return geo.AppleSettings(
        accuracy: geo.LocationAccuracy.medium,
        distanceFilter: 0,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const geo.LocationSettings(accuracy: geo.LocationAccuracy.medium);
  }

  @override
  Future<void> start({
    required String courierId,
    required String deviceId,
  }) async {
    if (_subscription != null) return;
    _subscription = geo.Geolocator.getPositionStream(
      locationSettings: _backgroundSettings(),
    ).listen(
      (_) {},
      onError: (_) {},
      cancelOnError: false,
    );
  }

  @override
  Future<void> stop({
    required String courierId,
    required String deviceId,
  }) async {
    await _subscription?.cancel();
    _subscription = null;
  }

  @override
  bool get isActive => _subscription != null;
}
