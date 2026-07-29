import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/build_courier_performance_snapshot.dart';
import '../../domain/delivery/delivery_failure.dart';
import '../../domain/delivery/delivery_failure_responsibility.dart';
import '../../domain/performance/courier_performance_snapshot.dart';
import '../providers/courier_dependencies_provider.dart';

/// Folds the Phase 5O brief's Courier Performance Summary and Failed
/// Delivery Review into one manager-facing screen — a courier's computed
/// [CourierPerformanceSnapshot] (never a score/rank, per its own
/// documented exclusion) plus every recorded [DeliveryFailure], grouped
/// by [DeliveryFailureResponsibility] so a manager can see at a glance
/// which failures were actually the courier's fault vs. the customer's/
/// restaurant's/system's/force-majeure.
class CourierPerformanceScreen extends ConsumerStatefulWidget {
  const CourierPerformanceScreen({super.key, required this.courierId});

  final String courierId;

  @override
  ConsumerState<CourierPerformanceScreen> createState() =>
      _CourierPerformanceScreenState();
}

class _CourierPerformanceScreenState
    extends ConsumerState<CourierPerformanceScreen> {
  CourierPerformanceSnapshot? _snapshot;
  List<DeliveryFailure>? _failures;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
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

    final deliveries = await ref
        .read(deliveryRepositoryProvider)
        .findByCourierId(widget.courierId);
    final failures = <DeliveryFailure>[];
    for (final delivery in deliveries) {
      failures.addAll(
        await ref
            .read(deliveryFailureRepositoryProvider)
            .findByDeliveryId(delivery.id),
      );
    }

    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _failures = failures;
    });
  }

  static const _responsibilityLabels = {
    DeliveryFailureResponsibility.customer: 'Müşteri',
    DeliveryFailureResponsibility.restaurant: 'Restoran',
    DeliveryFailureResponsibility.courier: 'Kurye',
    DeliveryFailureResponsibility.system: 'Sistem',
    DeliveryFailureResponsibility.forceMajeure: 'Mücbir Sebep',
    DeliveryFailureResponsibility.manager: 'Yönetici',
  };

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final failures = _failures;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Performansı'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: snapshot == null || failures == null
            ? const LoadingView(message: 'Performans yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _buildMetricsCard(snapshot),
                  const SizedBox(height: AppSpacing.lg),
                  _buildFailuresCard(failures),
                ],
              ),
      ),
    );
  }

  Widget _buildMetricsCard(CourierPerformanceSnapshot snapshot) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Son 30 Gün Metrikleri', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _statRow('Teklif Edilen Görev', '${snapshot.assignmentsOffered}'),
          _statRow('Kabul Edilen', '${snapshot.assignmentsAccepted}'),
          _statRow('Reddedilen', '${snapshot.assignmentsRejected}'),
          _statRow('Başarılı Teslimat', '${snapshot.successfulDeliveries}'),
          _statRow('Yeniden Atama', '${snapshot.reassignmentCount}'),
          _statRow('Konum Onayı Geçersiz Kılma',
              '${snapshot.geofenceOverrideCount}'),
          _statRow('Müşteri İletişim Girişimi',
              '${snapshot.customerContactAttempts}'),
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

  Widget _buildFailuresCard(List<DeliveryFailure> failures) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Başarısız Teslimat İncelemesi',
              style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (failures.isEmpty)
            const EmptyView(
              icon: Icons.check_circle_outline,
              message: 'Kayıtlı başarısız teslimat yok',
            )
          else
            for (final failure in failures)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(failure.reasonCode.name),
                subtitle:
                    Text(_responsibilityLabels[failure.responsibility] ?? ''),
                trailing: failure.responsibility ==
                        DeliveryFailureResponsibility.customer
                    ? const Icon(Icons.flag_outlined, color: AppColors.warning)
                    : null,
              ),
        ],
      ),
    );
  }
}
