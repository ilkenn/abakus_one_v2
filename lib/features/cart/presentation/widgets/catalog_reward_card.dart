import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../loyalty/domain/models/loyalty_reward.dart';

/// Boncuk Loyalty Program P7-C (2026-08-24) — the minimal Takeaway checkout
/// widget for selecting one catalog reward from the customer's real,
/// server-authoritative Reward Catalog (`loyaltyRewardCatalogProvider`).
/// Deliberately narrow in scope — a full Ödüller browsing/detail
/// experience is P7-D's own concern; this card exists only to let a
/// customer pick from the rewards actually eligible for their current
/// cart during checkout.
///
/// A presentational (dumb) widget: [rewardsAsync] and [cartProductIds] are
/// supplied by the caller; this card never calls the backend itself and
/// never invents a reward — every entry shown here came from a real
/// `getCustomerLoyaltyRewardCatalog` response.
///
/// **Mutual exclusivity with cash Boncuk redemption** is enforced by the
/// CALLER (`TakeawayCheckoutScreen`), not this widget — see that screen's
/// own selection-state handling. This card only renders/selects; it holds
/// no state of its own.
class CatalogRewardCard extends StatelessWidget {
  const CatalogRewardCard({
    super.key,
    required this.rewardsAsync,
    required this.cartProductIds,
    required this.selectedRewardId,
    required this.boncukCashRedemptionActive,
    required this.controlsFrozen,
    required this.onSelect,
    required this.onRetry,
  });

  final AsyncValue<List<LoyaltyReward>> rewardsAsync;
  final Set<String> cartProductIds;

  /// The customer's own explicit reward choice — `null` means none
  /// selected. Never silently chosen/cleared by this widget.
  final String? selectedRewardId;

  /// `true` when cash Boncuk redemption is currently the customer's
  /// selected benefit — this card disables itself entirely while that is
  /// true (one order = maximum one benefit), rather than allowing a
  /// doomed selection the server would reject anyway.
  final bool boncukCashRedemptionActive;

  final bool controlsFrozen;

  /// Tapping an already-selected reward calls this with `null` (deselect);
  /// tapping a different one calls this with its `rewardId`.
  final ValueChanged<String?> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (boncukCashRedemptionActive) return const SizedBox.shrink();

    return rewardsAsync.when(
      loading: () => const _CatalogRewardCardSkeleton(),
      error: (error, stackTrace) => _CatalogRewardCardError(onRetry: onRetry),
      data: (rewards) {
        final eligible = [
          for (final reward in rewards)
            if (reward.isEligibleForCart(cartProductIds)) reward,
        ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        if (eligible.isEmpty) return const SizedBox.shrink();

        return AppCard(
          key: const Key('catalogRewardCard'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Boncuk ile Ödül Kullan',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final reward in eligible)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _RewardTile(
                    key: Key('catalogRewardTile-${reward.rewardId}'),
                    reward: reward,
                    isSelected: selectedRewardId == reward.rewardId,
                    enabled: !controlsFrozen,
                    onTap: () => onSelect(
                      selectedRewardId == reward.rewardId
                          ? null
                          : reward.rewardId,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    super.key,
    required this.reward,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final LoyaltyReward reward;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: AppRadius.kMedium,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryExtraLight : AppColors.surface,
          borderRadius: AppRadius.kMedium,
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reward.title, style: AppTypography.bodyLarge),
                  Text(
                    reward.description,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${reward.boncukCost} Boncuk',
              style:
                  AppTypography.labelLarge.copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogRewardCardSkeleton extends StatelessWidget {
  const _CatalogRewardCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('catalogRewardCardSkeleton'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Ödüller yükleniyor...',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CatalogRewardCardError extends StatelessWidget {
  const _CatalogRewardCardError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('catalogRewardCardError'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Ödüllere şu anda ulaşılamıyor. Boncuk kullanmadan devam '
              'edebilirsin.',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
        ],
      ),
    );
  }
}
