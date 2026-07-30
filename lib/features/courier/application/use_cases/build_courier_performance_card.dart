import '../../domain/performance/courier_performance_card.dart';
import 'build_courier_earnings_summary.dart';
import 'build_courier_performance_snapshot.dart';

/// Assembles one courier's [CourierPerformanceCard] for `[periodStart,
/// periodEnd]` by calling the two already-existing, unmodified builders —
/// Sprint 5C Part 10. Pure composition: no new repository reads, no new
/// metric computation, matching this sprint's established
/// "aggregate, don't reinvent" pattern (`BuildCourierLiveWarnings`,
/// `BuildCourierMessageStatus`).
class BuildCourierPerformanceCard {
  const BuildCourierPerformanceCard({
    required BuildCourierPerformanceSnapshot buildPerformanceSnapshot,
    required BuildCourierEarningsSummary buildEarningsSummary,
  })  : _buildPerformanceSnapshot = buildPerformanceSnapshot,
        _buildEarningsSummary = buildEarningsSummary;

  final BuildCourierPerformanceSnapshot _buildPerformanceSnapshot;
  final BuildCourierEarningsSummary _buildEarningsSummary;

  Future<CourierPerformanceCard> call({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final performance = await _buildPerformanceSnapshot(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    final earnings = await _buildEarningsSummary(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    return CourierPerformanceCard(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      performance: performance,
      earnings: earnings,
    );
  }
}
