import 'package:abakus_one_v2/features/courier/domain/location/eta_historical_sample.dart';
import 'package:abakus_one_v2/features/courier/domain/location/historical_eta_average_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HistoricalEtaAverageCalculator.averageSpeedMetersPerSecond', () {
    test('fewer samples than the minimum returns null', () {
      final result = HistoricalEtaAverageCalculator.averageSpeedMetersPerSecond(
        samples: List.generate(
          3,
          (_) => const EtaHistoricalSample(
              distanceMeters: 1000, actualDurationSeconds: 100),
        ),
        minimumSampleCount: 5,
      );
      expect(result, isNull);
    });

    test('averages total distance over total duration across all samples', () {
      final result = HistoricalEtaAverageCalculator.averageSpeedMetersPerSecond(
        samples: const [
          EtaHistoricalSample(distanceMeters: 1000, actualDurationSeconds: 200),
          EtaHistoricalSample(distanceMeters: 2000, actualDurationSeconds: 400),
          EtaHistoricalSample(distanceMeters: 500, actualDurationSeconds: 100),
          EtaHistoricalSample(distanceMeters: 1500, actualDurationSeconds: 300),
          EtaHistoricalSample(distanceMeters: 1000, actualDurationSeconds: 200),
        ],
        minimumSampleCount: 5,
      );
      // total distance 6000m / total duration 1200s = 5 m/s
      expect(result, closeTo(5.0, 0.001));
    });

    test('zero total duration never divides by zero', () {
      final result = HistoricalEtaAverageCalculator.averageSpeedMetersPerSecond(
        samples: List.generate(
          5,
          (_) => const EtaHistoricalSample(
              distanceMeters: 100, actualDurationSeconds: 0),
        ),
        minimumSampleCount: 5,
      );
      expect(result, isNull);
    });
  });
}
