import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/rewards/reward_type.dart';
import '../../domain/rewards/visit_reward_rule.dart';
import '../../domain/visits/customer_visit_passport.dart';
import '../providers/crm_dependencies_provider.dart';

/// Customer-facing Visit Passport — Sprint 5D Part 1. Real domain data
/// (`CustomerVisitPassport`), not a UI mock — a new screen, deliberately
/// separate from `features/profile`'s existing `LoyaltyScreen`, which
/// remains untouched (see `docs/decisions.md` ADR-021).
///
/// **Sprint 5E**: reachable from `ProfileScreen`'s "Ziyaret Pasosu" entry
/// — the Phase 5 closure sprint's explicit, reasoned choice to keep this
/// and the Boncuk points program (`LoyaltyScreen`) as two honestly
/// separate, distinctly labeled programs rather than merging or replacing
/// either (`docs/decisions.md` ADR-022) — see `LoyaltyScreen`'s own doc
/// comment for the symmetric cross-reference.
class CustomerVisitPassportScreen extends ConsumerStatefulWidget {
  const CustomerVisitPassportScreen({
    super.key,
    required this.customerId,
    required this.branchId,
  });

  final String customerId;
  final String branchId;

  @override
  ConsumerState<CustomerVisitPassportScreen> createState() =>
      _CustomerVisitPassportScreenState();
}

class _CustomerVisitPassportScreenState
    extends ConsumerState<CustomerVisitPassportScreen> {
  CustomerVisitPassport? _passport;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final passport = await ref.read(buildCustomerVisitPassportProvider)(
      customerId: widget.customerId,
      branchId: widget.branchId,
    );
    if (!mounted) return;
    setState(() => _passport = passport);
  }

  static String _rewardLabel(RewardType type) {
    switch (type) {
      case RewardType.loyaltyPoints:
        return 'Puan';
      case RewardType.coupon:
        return 'Kupon';
      case RewardType.freeProduct:
        return 'Ücretsiz Ürün';
      case RewardType.freeDrink:
        return 'Ücretsiz İçecek';
      case RewardType.dessert:
        return 'Tatlı';
      case RewardType.upgrade:
        return 'Yükseltme';
      case RewardType.campaign:
        return 'Kampanya';
    }
  }

  @override
  Widget build(BuildContext context) {
    final passport = _passport;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ziyaret Pasosu'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: passport == null
            ? const LoadingView(message: 'Pasonuz yükleniyor...')
            : _buildBody(passport),
      ),
    );
  }

  Widget _buildBody(CustomerVisitPassport passport) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Toplam Ziyaret', style: AppTypography.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Text('${passport.totalVisitCount}',
                  style: AppTypography.displayMedium),
              if (passport.nextReward != null) ...[
                const SizedBox(height: AppSpacing.sm),
                LinearProgressIndicator(
                  value: passport.progressRatioTowardNextReward,
                  backgroundColor: AppColors.surface,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Sıradaki ödül: ${_rewardLabel(passport.nextReward!.rewardType)} '
                  '(${passport.nextReward!.requiredVisitCount} ziyarette)',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tamamlanan Ödüller', style: AppTypography.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              if (passport.completedRewards.isEmpty)
                Text('Henüz tamamlanan ödül yok.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary))
              else
                for (final VisitRewardRule reward in passport.completedRewards)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${_rewardLabel(reward.rewardType)} — '
                      '${reward.requiredVisitCount} ziyaret',
                      style: AppTypography.bodyMedium,
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ödül Geçmişi', style: AppTypography.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              if (passport.rewardHistory.isEmpty)
                Text('Henüz kazanılan ödül yok.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary))
              else
                for (final grant in passport.rewardHistory)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${_rewardLabel(grant.rewardType)} — '
                      '${grant.visitCountAtGrant}. ziyarette kazanıldı',
                      style: AppTypography.bodyMedium,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
