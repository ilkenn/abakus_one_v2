import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/models/loyalty_reward.dart';
import '../providers/loyalty_providers.dart';
import 'reward_detail_screen.dart';

/// Boncuk Loyalty Program P7-D (2026-08-24) — "Boncuklarım → Ödüller": the
/// real customer Reward Catalog listing. Sourced exclusively from
/// [loyaltyRewardCatalogProvider] (`getCustomerLoyaltyRewardCatalog`,
/// P7-B/P7-C.1's own sanitized server DTO) — no mock reward source is
/// reachable from here or anywhere downstream of it.
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewardsAsync = ref.watch(loyaltyRewardCatalogProvider);
    final snapshotAsync = ref.watch(loyaltySnapshotProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ödüller'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: rewardsAsync.when(
          loading: () => const LoadingView(message: 'Ödüller yükleniyor...'),
          error: (error, stackTrace) => ErrorView(
            message: 'Ödüller şu anda yüklenemedi.',
            retryLabel: 'Tekrar Dene',
            onRetry: () => ref.invalidate(loyaltyRewardCatalogProvider),
          ),
          data: (rewards) {
            if (rewards.isEmpty) {
              return const EmptyView(
                icon: Icons.redeem_rounded,
                message: 'Şu anda kullanılabilir bir ödül yok.',
              );
            }
            final sorted = [...rewards]
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
            final spendableBalance =
                snapshotAsync.valueOrNull?.spendableBalance;
            return RefreshIndicator(
              onRefresh: () => ref.refresh(loyaltyRewardCatalogProvider.future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  for (final reward in sorted) ...[
                    _RewardCard(
                      key: Key('rewardCard-${reward.rewardId}'),
                      reward: reward,
                      spendableBalance: spendableBalance,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              RewardDetailScreen(reward: reward),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    super.key,
    required this.reward,
    required this.spendableBalance,
    required this.onTap,
  });

  final LoyaltyReward reward;

  /// `null` while the balance is still loading/unavailable — the
  /// affordability badge is simply omitted in that case, never guessed.
  final int? spendableBalance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final balance = spendableBalance;
    final canAfford = balance != null && balance >= reward.boncukCost;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.kMedium,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: const BoxDecoration(
                color: AppColors.primaryExtraLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.redeem_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reward.title,
                    style: AppTypography.bodyLarge
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reward.description,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: canAfford
                              ? AppColors.primaryExtraLight
                              : AppColors.surfaceVariant,
                          borderRadius: AppRadius.kPill,
                        ),
                        child: Text(
                          '${reward.boncukCost} Boncuk',
                          style: AppTypography.labelLarge.copyWith(
                            color: canAfford
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (balance != null && !canAfford) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '${reward.boncukCost - balance} Boncuk daha gerekli',
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
