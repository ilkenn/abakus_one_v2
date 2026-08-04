import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_environment_config_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/build_release_readiness_snapshot.dart';
import '../../domain/release_readiness_criterion_status.dart';
import '../../domain/release_readiness_snapshot.dart';
import '../providers/platform_actor_session_provider.dart';

/// Release Readiness — Phase 8P/8R (`docs/decisions.md` ADR-025). The
/// first screen surfacing [BuildReleaseReadinessSnapshot]'s honest
/// checklist to a real platform-level actor. A readiness *record*
/// only — nothing here publishes or submits a build anywhere.
class ReleaseReadinessScreen extends ConsumerStatefulWidget {
  const ReleaseReadinessScreen({super.key});

  @override
  ConsumerState<ReleaseReadinessScreen> createState() =>
      _ReleaseReadinessScreenState();
}

class _ReleaseReadinessScreenState
    extends ConsumerState<ReleaseReadinessScreen> {
  ReleaseReadinessSnapshot? _snapshot;
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
      final snapshot = await BuildReleaseReadinessSnapshot(
        authorizationPolicy: ref.read(platformAuthorizationPolicyProvider),
        environmentConfig: ref.read(appEnvironmentConfigProvider),
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
      return const LoadingView(message: 'Yayın hazırlığı yükleniyor...');
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                snapshot.isReleaseReady
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color: snapshot.isReleaseReady
                    ? AppColors.success
                    : AppColors.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  snapshot.isReleaseReady
                      ? 'Yayına hazır'
                      : '${snapshot.blockingCriteria.length} kriter '
                          'yayına hazır değil',
                  style: AppTypography.bodyLarge,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final criterion in snapshot.criteria)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusIcon(status: criterion.status),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(criterion.label,
                            style: AppTypography.bodyLarge),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(criterion.note,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final ReleaseReadinessCriterionStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ReleaseReadinessCriterionStatus.ready:
        return const Icon(Icons.check_circle_outline, color: AppColors.success);
      case ReleaseReadinessCriterionStatus.notReady:
        return const Icon(Icons.cancel_outlined, color: AppColors.error);
      case ReleaseReadinessCriterionStatus.manualStepRequired:
        return const Icon(Icons.warning_amber_outlined,
            color: AppColors.warning);
    }
  }
}
