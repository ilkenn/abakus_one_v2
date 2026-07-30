import 'package:abakus_one_v2/features/courier/domain/location/signal_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SignalQualityClassifier.classify', () {
    test('at or below the good threshold classifies as good', () {
      expect(SignalQualityClassifier.classify(10), SignalQuality.good);
      expect(SignalQualityClassifier.classify(20), SignalQuality.good);
    });

    test('between the good and fair thresholds classifies as fair', () {
      expect(SignalQualityClassifier.classify(21), SignalQuality.fair);
      expect(SignalQualityClassifier.classify(50), SignalQuality.fair);
    });

    test('above the fair threshold classifies as poor', () {
      expect(SignalQualityClassifier.classify(51), SignalQuality.poor);
      expect(SignalQualityClassifier.classify(500), SignalQuality.poor);
    });

    test(
        'the fair threshold defaults to the geofence-trusted accuracy '
        'cutoff, so "fair" always means "still trusted"', () {
      // GeofenceEvaluator.maxTrustedAccuracyMeters == 50.
      expect(SignalQualityClassifier.classify(50), SignalQuality.fair);
      expect(SignalQualityClassifier.classify(50.01), SignalQuality.poor);
    });

    test('thresholds are adjustable via parameters, never hardcoded', () {
      expect(
        SignalQualityClassifier.classify(
          5,
          goodThresholdMeters: 2,
          fairThresholdMeters: 8,
        ),
        SignalQuality.fair,
      );
    });
  });
}
