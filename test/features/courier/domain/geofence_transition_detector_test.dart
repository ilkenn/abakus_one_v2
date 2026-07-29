import 'package:abakus_one_v2/features/courier/domain/location/geofence_evaluation_result.dart';
import 'package:abakus_one_v2/features/courier/domain/location/geofence_transition_detector.dart';
import 'package:abakus_one_v2/features/courier/domain/location/geofence_transition_type.dart';
import 'package:flutter_test/flutter_test.dart';

GeofenceEvaluationResult _result({
  required bool isWithin,
  bool isAccuracySufficient = true,
  double distanceMeters = 10,
}) {
  return GeofenceEvaluationResult(
    isWithin: isWithin,
    distanceMeters: distanceMeters,
    isAccuracySufficient: isAccuracySufficient,
  );
}

void main() {
  group('GeofenceTransitionDetector.detect', () {
    test('no previous evaluation + currently inside confirms an entry', () {
      final transition = GeofenceTransitionDetector.detect(
        previous: null,
        current: _result(isWithin: true),
      );
      expect(transition, GeofenceTransitionType.entered);
    });

    test('no previous evaluation + currently outside is not a transition', () {
      final transition = GeofenceTransitionDetector.detect(
        previous: null,
        current: _result(isWithin: false),
      );
      expect(transition, isNull);
    });

    test('outside -> inside confirms an entry', () {
      final transition = GeofenceTransitionDetector.detect(
        previous: _result(isWithin: false),
        current: _result(isWithin: true),
      );
      expect(transition, GeofenceTransitionType.entered);
    });

    test('inside -> outside confirms an exit', () {
      final transition = GeofenceTransitionDetector.detect(
        previous: _result(isWithin: true),
        current: _result(isWithin: false),
      );
      expect(transition, GeofenceTransitionType.exited);
    });

    test('no state change never produces a transition (no spam)', () {
      expect(
        GeofenceTransitionDetector.detect(
          previous: _result(isWithin: true),
          current: _result(isWithin: true),
        ),
        isNull,
      );
      expect(
        GeofenceTransitionDetector.detect(
          previous: _result(isWithin: false),
          current: _result(isWithin: false),
        ),
        isNull,
      );
    });

    test(
        'low-accuracy current reading never confirms a transition, even a '
        'real state change', () {
      final transition = GeofenceTransitionDetector.detect(
        previous: _result(isWithin: false),
        current: _result(isWithin: true, isAccuracySufficient: false),
      );
      expect(transition, isNull);
    });
  });
}
