import '../../data/delivery_earnings_repository.dart';
import '../../data/delivery_repository.dart';
import '../../data/courier_repository.dart';
import '../../domain/analytics/courier_daily_operations_report.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/performance/courier_performance_snapshot.dart';
import 'build_courier_performance_snapshot.dart';

/// Assembles the branch's [CourierDailyOperationsReport] for one calendar
/// day — Sprint 5C Part 12. Aggregates over every courier eligible for
/// the branch (mirrors `BuildCourierLiveWarnings`'s per-courier-then-
/// merge shape); no repository interface changes were needed since
/// [DeliveryRepository] already exposes `findByCourierId`.
class BuildCourierDailyOperationsReport {
  const BuildCourierDailyOperationsReport({
    required CourierRepository courierRepository,
    required DeliveryRepository deliveryRepository,
    required DeliveryEarningsRepository deliveryEarningsRepository,
    required BuildCourierPerformanceSnapshot buildCourierPerformanceSnapshot,
  })  : _courierRepository = courierRepository,
        _deliveryRepository = deliveryRepository,
        _deliveryEarningsRepository = deliveryEarningsRepository,
        _buildCourierPerformanceSnapshot = buildCourierPerformanceSnapshot;

  final CourierRepository _courierRepository;
  final DeliveryRepository _deliveryRepository;
  final DeliveryEarningsRepository _deliveryEarningsRepository;
  final BuildCourierPerformanceSnapshot _buildCourierPerformanceSnapshot;

  /// [date] may be any [DateTime] within the target day — only its
  /// year/month/day are used; the report always covers a full local-day
  /// window.
  Future<CourierDailyOperationsReport> call({
    required String branchId,
    required DateTime date,
  }) async {
    final periodStart = DateTime(date.year, date.month, date.day);
    final periodEnd = periodStart.add(const Duration(days: 1));

    final couriers = await _courierRepository.findByBranchId(branchId);

    var totalDeliveries = 0;
    var totalDurationSeconds = 0.0;
    var totalDistanceKm = 0.0;
    final hourCounts = <int, int>{};
    final performanceSnapshots = <CourierPerformanceSnapshot>[];

    for (final courier in couriers) {
      final deliveries = await _deliveryRepository.findByCourierId(courier.id);
      for (final delivery in deliveries) {
        final deliveredAt = delivery.deliveredAt;
        if (delivery.status != DeliveryStatus.delivered ||
            deliveredAt == null) {
          continue;
        }
        if (deliveredAt.isBefore(periodStart) ||
            !deliveredAt.isBefore(periodEnd)) {
          continue;
        }
        totalDeliveries++;
        totalDurationSeconds +=
            deliveredAt.difference(delivery.createdAt).inSeconds.toDouble();
        hourCounts[deliveredAt.hour] = (hourCounts[deliveredAt.hour] ?? 0) + 1;
      }

      final earnings =
          await _deliveryEarningsRepository.findByCourierIdAndPeriod(
        courierId: courier.id,
        periodStart: periodStart,
        periodEnd: periodEnd,
      );
      for (final earning in earnings) {
        totalDistanceKm += earning.distanceKm;
      }

      performanceSnapshots.add(await _buildCourierPerformanceSnapshot(
        courierId: courier.id,
        periodStart: periodStart,
        periodEnd: periodEnd,
      ));
    }

    int? peakHour;
    if (hourCounts.isNotEmpty) {
      peakHour =
          hourCounts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    }

    return CourierDailyOperationsReport(
      branchId: branchId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      totalDeliveries: totalDeliveries,
      totalDistanceTravelledKm: totalDistanceKm,
      averageDeliveryDurationSeconds:
          totalDeliveries == 0 ? null : totalDurationSeconds / totalDeliveries,
      peakHour: peakHour,
      courierPerformance: performanceSnapshots,
    );
  }
}
