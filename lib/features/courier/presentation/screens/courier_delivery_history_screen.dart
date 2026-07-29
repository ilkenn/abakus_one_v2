import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/build_courier_performance_snapshot.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/performance/courier_performance_snapshot.dart';
import '../providers/courier_dependencies_provider.dart';

/// Folds the Phase 5N brief's "Delivery History" and "Shift Summary"
/// screens into one — a courier's full delivery list plus the computed
/// [CourierPerformanceSnapshot] for the same period, since both are
/// read-only views over the same underlying data.
class CourierDeliveryHistoryScreen extends ConsumerStatefulWidget {
  const CourierDeliveryHistoryScreen({super.key, required this.courierId});

  final String courierId;

  @override
  ConsumerState<CourierDeliveryHistoryScreen> createState() =>
      _CourierDeliveryHistoryScreenState();
}

class _CourierDeliveryHistoryScreenState
    extends ConsumerState<CourierDeliveryHistoryScreen> {
  List<Delivery>? _deliveries;
  CourierPerformanceSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final deliveries = await ref
        .read(deliveryRepositoryProvider)
        .findByCourierId(widget.courierId);
    final periodEnd = DateTime.now();
    final periodStart = periodEnd.subtract(const Duration(days: 30));
    final snapshot = await BuildCourierPerformanceSnapshot(
      deliveryRepository: ref.read(deliveryRepositoryProvider),
      assignmentRepository: ref.read(deliveryAssignmentRepositoryProvider),
      failureRepository: ref.read(deliveryFailureRepositoryProvider),
      geofenceOverrideRepository: ref.read(geofenceOverrideRepositoryProvider),
      contactActionRepository:
          ref.read(customerContactActionRepositoryProvider),
    )(
      courierId: widget.courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    if (!mounted) return;
    setState(() {
      _deliveries = deliveries.reversed.toList();
      _snapshot = snapshot;
    });
  }

  @override
  Widget build(BuildContext context) {
    final deliveries = _deliveries;
    final snapshot = _snapshot;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Teslimat Geçmişi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: deliveries == null || snapshot == null
            ? const LoadingView(message: 'Geçmiş yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _buildSummaryCard(snapshot),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Teslimatlar', style: AppTypography.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  if (deliveries.isEmpty)
                    const EmptyView(
                      icon: Icons.local_shipping_outlined,
                      message: 'Henüz teslimat yok',
                    )
                  else
                    for (final delivery in deliveries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ListTile(
                          tileColor: AppColors.surface,
                          title: Text('Sipariş: ${delivery.orderId.value}'),
                          subtitle: Text(delivery.status.name),
                          trailing: Icon(
                            delivery.status == DeliveryStatus.delivered
                                ? Icons.check_circle
                                : Icons.info_outline,
                            color: delivery.status == DeliveryStatus.delivered
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                ],
              ),
      ),
    );
  }

  Widget _buildSummaryCard(CourierPerformanceSnapshot snapshot) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Son 30 Gün', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _statRow('Tamamlanan Teslimat', '${snapshot.successfulDeliveries}'),
          _statRow('Kabul Edilen Görev', '${snapshot.assignmentsAccepted}'),
          _statRow('Reddedilen Görev', '${snapshot.assignmentsRejected}'),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          Text(value, style: AppTypography.bodyMedium),
        ],
      ),
    );
  }
}
