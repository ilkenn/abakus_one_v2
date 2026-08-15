import 'package:abakus_one_v2/core/fraud/domain/mock_location_status.dart';
import 'package:abakus_one_v2/features/address_search/data/address_location_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

geo.Position _position({bool isMocked = false}) {
  return geo.Position(
    latitude: 41.0449616,
    longitude: 29.0076831,
    timestamp: DateTime(2026, 8, 15, 9, 0),
    accuracy: 12.5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
    isMocked: isMocked,
  );
}

void main() {
  group('unavailableReasonFor (pure, FRAUD-F.1)', () {
    test('permission denied forever returns permissionDeniedForever', () {
      expect(
        unavailableReasonFor(geo.LocationPermission.deniedForever,
            serviceEnabled: true),
        DeviceLocationUnavailableReason.permissionDeniedForever,
      );
    });

    test('permission denied returns permissionDenied', () {
      expect(
        unavailableReasonFor(geo.LocationPermission.denied,
            serviceEnabled: true),
        DeviceLocationUnavailableReason.permissionDenied,
      );
    });

    test('permission granted but service disabled returns serviceDisabled', () {
      expect(
        unavailableReasonFor(geo.LocationPermission.whileInUse,
            serviceEnabled: false),
        DeviceLocationUnavailableReason.serviceDisabled,
      );
    });

    test('permission granted and service enabled returns null (proceed to capture)', () {
      expect(
        unavailableReasonFor(geo.LocationPermission.always,
            serviceEnabled: true),
        isNull,
      );
    });
  });

  group('mockLocationStatusFor (pure, FRAUD-F.1)', () {
    test('iOS always maps to unsupported, regardless of isMocked', () {
      expect(
        mockLocationStatusFor(_position(isMocked: true), isAndroid: false),
        MockLocationStatus.unsupported,
      );
      expect(
        mockLocationStatusFor(_position(isMocked: false), isAndroid: false),
        MockLocationStatus.unsupported,
      );
    });

    test('Android with isMocked=true maps to detected', () {
      expect(
        mockLocationStatusFor(_position(isMocked: true), isAndroid: true),
        MockLocationStatus.detected,
      );
    });

    test('Android with isMocked=false maps to notDetected', () {
      expect(
        mockLocationStatusFor(_position(isMocked: false), isAndroid: true),
        MockLocationStatus.notDetected,
      );
    });
  });

  group('precisionStateFor (pure, FRAUD-F.1)', () {
    test('precise maps to "precise"', () {
      expect(precisionStateFor(geo.LocationAccuracyStatus.precise), 'precise');
    });

    test('reduced maps to "reduced"', () {
      expect(precisionStateFor(geo.LocationAccuracyStatus.reduced), 'reduced');
    });

    test('unknown maps to "unknown"', () {
      expect(precisionStateFor(geo.LocationAccuracyStatus.unknown), 'unknown');
    });
  });

  group('clientLocationEvidenceFrom (pure, FRAUD-F.1)', () {
    test('captures latitude/longitude/accuracyMeters exactly from the position', () {
      final evidence = clientLocationEvidenceFrom(
        _position(),
        accuracyStatus: geo.LocationAccuracyStatus.precise,
        isAndroid: true,
      );

      expect(evidence.latitude, 41.0449616);
      expect(evidence.longitude, 29.0076831);
      expect(evidence.accuracyMeters, 12.5);
    });

    test('clientCapturedAt provenance is the device position timestamp, exactly', () {
      final timestamp = DateTime(2026, 8, 15, 9, 0);
      final position = geo.Position(
        latitude: 41.0,
        longitude: 29.0,
        timestamp: timestamp,
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      final evidence = clientLocationEvidenceFrom(
        position,
        accuracyStatus: geo.LocationAccuracyStatus.unknown,
        isAndroid: true,
      );

      expect(evidence.clientCapturedAt, timestamp);
    });

    test('permissionState is always "granted" — a candidate only ever exists when permission was granted', () {
      final evidence = clientLocationEvidenceFrom(
        _position(),
        accuracyStatus: geo.LocationAccuracyStatus.precise,
        isAndroid: true,
      );

      expect(evidence.permissionState, 'granted');
    });

    test('unsupported platform behavior: iOS never reports detected/notDetected, only unsupported', () {
      final evidence = clientLocationEvidenceFrom(
        _position(isMocked: true),
        accuracyStatus: geo.LocationAccuracyStatus.precise,
        isAndroid: false,
      );

      expect(evidence.mockLocationStatus, MockLocationStatus.unsupported);
    });
  });
}
