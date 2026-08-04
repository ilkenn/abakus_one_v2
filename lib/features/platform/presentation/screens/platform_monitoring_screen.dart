import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../integrations/presentation/providers/integration_dependencies_provider.dart';
import '../../application/use_cases/build_platform_monitoring_snapshot.dart';
import '../../domain/platform_monitoring_snapshot.dart';
import '../providers/platform_actor_session_provider.dart';
import '../providers/platform_dependencies_provider.dart';

/// Platform Monitoring — Phase 8O/8R (`docs/decisions.md` ADR-025). The
/// first screen surfacing [BuildPlatformMonitoringSnapshot]'s
/// cross-tenant read-model to a real platform-level actor.
class PlatformMonitoringScreen extends ConsumerStatefulWidget {
  const PlatformMonitoringScreen({super.key});

  @override
  ConsumerState<PlatformMonitoringScreen> createState() =>
      _PlatformMonitoringScreenState();
}

class _PlatformMonitoringScreenState
    extends ConsumerState<PlatformMonitoringScreen> {
  PlatformMonitoringSnapshot? _snapshot;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final actorId = ref.read(platformActorSessionProvider)?.actorId;
    if (actorId == null) return;
    try {
      final snapshot = await BuildPlatformMonitoringSnapshot(
        authorizationPolicy: ref.read(platformAuthorizationPolicyProvider),
        organizationRepository: ref.read(organizationRepositoryProvider),
        platformMemberRepository: ref.read(platformMemberRepositoryProvider),
        tenantIntegrationRepository:
            ref.read(tenantIntegrationConfigurationRepositoryProvider),
      )(actorId: actorId);
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ErrorView(
          message: _error!, retryLabel: 'Tekrar Dene', onRetry: _load);
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const LoadingView(message: 'Platform durumu yükleniyor...');
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                  label: 'Kiracı Organizasyon',
                  value: snapshot.organizationCount),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricCard(
                  label: 'Platform Üyesi', value: snapshot.platformMemberCount),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricCard(
                  label: 'Etkin Entegrasyon',
                  value: snapshot.tenantIntegrationEnabledCount),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Durgun Servisler', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final note in snapshot.dormantServiceNotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(note,
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Oluşturulma: ${snapshot.generatedAt}',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
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
    );
  }
}
