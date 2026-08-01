import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../courier/domain/health/courier_operation_health_level.dart';
import '../../../courier/presentation/providers/courier_location_tracking_dependencies_provider.dart';
import '../../../courier/presentation/providers/courier_core_dependencies_provider.dart';
import '../../../crm/presentation/providers/crm_dependencies_provider.dart';
import '../../../feedback/presentation/providers/feedback_dependencies_provider.dart';
import '../../application/use_cases/build_admin_overview_snapshot.dart';
import '../../domain/overview/admin_overview_snapshot.dart';
import '../providers/admin_dependencies_provider.dart';

/// The Admin Overview — Phase 6E (`docs/decisions.md` ADR-023). Displays
/// only real, queryable projections (see `BuildAdminOverviewSnapshot`'s
/// own doc comment for exactly what's included and what's honestly
/// omitted), plus quick links into the modules those numbers come from.
class AdminOverviewScreen extends ConsumerStatefulWidget {
  const AdminOverviewScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<AdminOverviewScreen> createState() =>
      _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends ConsumerState<AdminOverviewScreen> {
  AdminOverviewSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final snapshot = await BuildAdminOverviewSnapshot(
      clock: ref.read(clockProvider),
      branchRepository: ref.read(branchRepositoryProvider),
      courierRepository: ref.read(courierRepositoryProvider),
      courierAvailabilityRepository:
          ref.read(courierAvailabilityRepositoryProvider),
      buildCourierOperationHealth:
          ref.read(buildCourierOperationHealthProvider),
      feedbackRepository: ref.read(customerFeedbackRepositoryProvider),
      feedbackStatusEventRepository:
          ref.read(customerFeedbackStatusEventRepositoryProvider),
      surveyRepository: ref.read(surveyRepositoryProvider),
      campaignRepository:
          ref.read(customerNotificationCampaignRepositoryProvider),
      auditRepository: ref.read(adminAuditEntryRepositoryProvider),
    )(branchId: widget.branchId);
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Genel Bakış'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: snapshot == null
            ? const LoadingView(message: 'Özet yükleniyor...')
            : _buildBody(snapshot),
      ),
    );
  }

  Widget _buildBody(AdminOverviewSnapshot snapshot) {
    final healthColor = switch (snapshot.operationHealth.level) {
      CourierOperationHealthLevel.healthy => AppColors.success,
      CourierOperationHealthLevel.degraded => AppColors.warning,
      CourierOperationHealthLevel.critical => AppColors.error,
    };
    final healthLabel = switch (snapshot.operationHealth.level) {
      CourierOperationHealthLevel.healthy => 'Sağlıklı',
      CourierOperationHealthLevel.degraded => 'Dikkat',
      CourierOperationHealthLevel.critical => 'Kritik',
    };

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.circle, color: healthColor, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Text('Operasyonel Durum: $healthLabel',
                  style: AppTypography.titleMedium),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _StatCard(label: 'Aktif Şube', value: snapshot.activeBranchCount),
            _StatCard(
                label: 'Bekleyen Teslimat',
                value: snapshot.waitingDeliveryCount),
            _StatCard(label: 'Aktif Kurye', value: snapshot.activeCourierCount),
            _StatCard(
                label: 'Çözülmemiş Geri Bildirim',
                value: snapshot.unresolvedFeedbackCount),
            _StatCard(label: 'Aktif Anket', value: snapshot.pendingSurveyCount),
            _StatCard(
                label: 'Bekleyen Kampanya',
                value: snapshot.pendingCampaignCount),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Son Denetim Kayıtları', style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        if (snapshot.recentCriticalAuditDescriptions.isEmpty)
          Text('Henüz kayıt yok.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary))
        else
          for (final description in snapshot.recentCriticalAuditDescriptions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(description, style: AppTypography.bodySmall),
            ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: AppTypography.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(label,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
