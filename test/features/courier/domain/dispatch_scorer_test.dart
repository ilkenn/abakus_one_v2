import 'package:abakus_one_v2/features/courier/domain/dispatch/dispatch_scorer.dart';
import 'package:abakus_one_v2/features/courier/domain/dispatch/dispatch_scoring_input.dart';
import 'package:flutter_test/flutter_test.dart';

DispatchScoringInput _candidate({
  required String courierId,
  bool isAvailable = true,
  bool isEligibleForBranch = true,
  int activeDeliveryCount = 0,
  int capacity = 3,
  double? distanceEstimateMeters,
  int packageWaitSeconds = 0,
  int recentRejectionCount = 0,
  bool isVehicleSuitable = true,
  bool isTemporarilyBlockedFromNewPackages = false,
}) {
  return DispatchScoringInput(
    courierId: courierId,
    isAvailable: isAvailable,
    isEligibleForBranch: isEligibleForBranch,
    activeDeliveryCount: activeDeliveryCount,
    capacity: capacity,
    distanceEstimateMeters: distanceEstimateMeters,
    packageWaitSeconds: packageWaitSeconds,
    recentRejectionCount: recentRejectionCount,
    isVehicleSuitable: isVehicleSuitable,
    isTemporarilyBlockedFromNewPackages: isTemporarilyBlockedFromNewPackages,
  );
}

void main() {
  group('DispatchScorer', () {
    test('an offline courier is ineligible and scores zero', () {
      final results = DispatchScorer.rank(
          [_candidate(courierId: 'c1', isAvailable: false)]);
      expect(results.single.isEligible, isFalse);
      expect(results.single.score, 0);
    });

    test('a courier at full capacity is ineligible', () {
      final results = DispatchScorer.rank([
        _candidate(courierId: 'c1', activeDeliveryCount: 3, capacity: 3),
      ]);
      expect(results.single.isEligible, isFalse);
    });

    test('a courier at the wrong branch is ineligible', () {
      final results = DispatchScorer.rank([
        _candidate(courierId: 'c1', isEligibleForBranch: false),
      ]);
      expect(results.single.isEligible, isFalse);
    });

    test('an unsuitable vehicle is ineligible', () {
      final results = DispatchScorer.rank([
        _candidate(courierId: 'c1', isVehicleSuitable: false),
      ]);
      expect(results.single.isEligible, isFalse);
    });

    test(
        'a courier temporarily blocked from new packages is ineligible '
        '(Sprint 5C)', () {
      final results = DispatchScorer.rank([
        _candidate(courierId: 'c1', isTemporarilyBlockedFromNewPackages: true),
      ]);
      expect(results.single.isEligible, isFalse);
      expect(results.single.score, 0);
    });

    test('closer candidates rank above farther ones, all else equal', () {
      final results = DispatchScorer.rank([
        _candidate(courierId: 'far', distanceEstimateMeters: 4500),
        _candidate(courierId: 'near', distanceEstimateMeters: 100),
      ]);
      expect(results.first.courierId, 'near');
      expect(results.first.score, greaterThan(results.last.score));
    });

    test('recent rejections lower priority but never eliminate a candidate',
        () {
      final results = DispatchScorer.rank([
        _candidate(
            courierId: 'rejector',
            distanceEstimateMeters: 500,
            recentRejectionCount: 5),
        _candidate(courierId: 'clean', distanceEstimateMeters: 500),
      ]);
      final rejector = results.firstWhere((r) => r.courierId == 'rejector');
      final clean = results.firstWhere((r) => r.courierId == 'clean');
      expect(rejector.isEligible, isTrue);
      expect(rejector.score, lessThan(clean.score));
    });

    test('ranking sorts descending by score', () {
      final results = DispatchScorer.rank([
        _candidate(courierId: 'far', distanceEstimateMeters: 4900),
        _candidate(courierId: 'near', distanceEstimateMeters: 50),
        _candidate(courierId: 'offline', isAvailable: false),
      ]);
      expect(results.map((r) => r.courierId), ['near', 'far', 'offline']);
    });
  });
}
