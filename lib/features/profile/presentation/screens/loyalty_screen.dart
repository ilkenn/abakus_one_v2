import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../shared/widgets/badges/boncuk_balance_pill.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/cards/loyalty_campaign_card.dart';
import '../../../../shared/widgets/misc/spin_wheel_icon.dart';
import '../../domain/models/loyalty_level.dart';
import '../../domain/models/loyalty_reward_model.dart';
import '../providers/loyalty_provider.dart';

/// The **Boncuk points program** (balance/tier, daily tasks, redeemable-
/// reward catalog, spin wheel) — mock/UI-only, `LoyaltyProvider`.
///
/// **Sprint 5E — deliberately kept separate from, not merged with, the
/// real Visit Passport program** (`features/crm`'s
/// `CustomerVisitPassportScreen`, "Ziyaret Pasosu" in `ProfileScreen`):
/// the two are genuinely different mechanics (points/spin/tasks vs.
/// visit-count thresholds) with no data overlap, and swapping this
/// screen out for the new one would have silently deleted real (if mock)
/// functionality the Phase 5 closure sprint was explicitly told not to
/// remove without documenting the migration. `docs/decisions.md`
/// ADR-022 records this reconciliation decision in full — this is not an
/// oversight, it's the chosen resolution among the three options that
/// sprint was offered.
class LoyaltyScreen extends ConsumerWidget {
  const LoyaltyScreen({super.key});

  void _showRedeemDialog(
    BuildContext context,
    WidgetRef ref,
    String title,
    int cost,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ödülü Kullan'),
        content: Text(
          '$title için $cost boncuk harcamak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              ref.read(loyaltyProvider.notifier).redeemReward(title, cost);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '$title başarıyla aktif edildi! Kodunuz profilinize tanımlandı.',
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: const Text(
              'Onayla',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _spin(BuildContext context, WidgetRef ref) {
    final reward = ref.read(loyaltyProvider.notifier).spinWheel();
    if (reward == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tebrikler, +$reward Boncuk kazandın! 🎉'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loyaltyState = ref.watch(loyaltyProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Boncuklarım 🌿'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.lg),
            child: BoncukBalancePill(),
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              'Yedikçe biriktir, biriktirdikçe kazan! 🌿',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _BalanceHeroCard(loyaltyState: loyaltyState),
            const SizedBox(height: AppSpacing.xxl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Boncuklarını Harca',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _RewardsGrid(
              rewards: loyaltyState.rewards,
              balance: loyaltyState.currentBalance,
              onRedeem: (title, cost) =>
                  _showRedeemDialog(context, ref, title, cost),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _SpinWheelCard(
              spinAvailable: loyaltyState.dailySpinAvailable,
              onSpin: () => _spin(context, ref),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _HowToEarnCard(),
            const SizedBox(height: AppSpacing.xl),
            if (loyaltyState.campaigns.isNotEmpty) ...[
              Text(
                'Boncuk Kampanyaları',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final campaign in loyaltyState.campaigns)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: LoyaltyCampaignCard(campaign: campaign),
                ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              'Boncuk Geçmişi',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.kMedium,
                border: Border.all(color: AppColors.border),
              ),
              child: Material(
                color: AppColors.surface,
                borderRadius: AppRadius.kMedium,
                clipBehavior: Clip.antiAlias,
                child: loyaltyState.history.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Center(
                          child: Text('İşlem geçmişi bulunmuyor.'),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: loyaltyState.history.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: AppColors.border, height: 1),
                        itemBuilder: (context, index) {
                          final item = loyaltyState.history[index];
                          return ListTile(
                            title: Text(
                              item.title,
                              style: AppTypography.bodyLarge,
                            ),
                            subtitle: Text(
                              item.date,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            trailing: Text(
                              item.isEarned
                                  ? '+${item.points}'
                                  : '-${item.points}',
                              style: AppTypography.titleMedium.copyWith(
                                color: item.isEarned
                                    ? AppColors.success
                                    : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceHeroCard extends StatelessWidget {
  final LoyaltyState loyaltyState;

  const _BalanceHeroCard({required this.loyaltyState});

  @override
  Widget build(BuildContext context) {
    final next = loyaltyState.nextLevel;
    final currentThreshold = LoyaltyLevelInfo.thresholdFor(
      loyaltyState.level,
    );
    final nextThreshold =
        next != null ? LoyaltyLevelInfo.thresholdFor(next) : currentThreshold;
    final progress = next == null
        ? 1.0
        : ((loyaltyState.currentBalance - currentThreshold) /
                (nextThreshold - currentThreshold))
            .clamp(0.0, 1.0);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.primaryExtraLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toplam Boncuk',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${loyaltyState.currentBalance}',
                      style: AppTypography.displayMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Harcamaya hazır boncukların',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('Boncuk Geçmişim'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: AppRadius.kMedium,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        next == null
                            ? '${LoyaltyLevelInfo.labelFor(loyaltyState.level)} — en üst seviyedesin!'
                            : '${LoyaltyLevelInfo.labelFor(next)} seviyeye ulaşmak için ${loyaltyState.pointsToNextLevel} boncuğa ihtiyacın var.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: AppRadius.kPill,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.border,
                    color: AppColors.primary,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${loyaltyState.currentBalance} / $nextThreshold',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardsGrid extends StatelessWidget {
  final List<LoyaltyRewardModel> rewards;
  final int balance;
  final void Function(String title, int cost) onRedeem;

  const _RewardsGrid({
    required this.rewards,
    required this.balance,
    required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rewards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (context, index) {
        final reward = rewards[index];
        final canRedeem = balance >= reward.cost;
        return _RewardCard(
          reward: reward,
          canRedeem: canRedeem,
          onRedeem: () => onRedeem(reward.title, reward.cost),
        );
      },
    );
  }
}

class _RewardCard extends StatelessWidget {
  final LoyaltyRewardModel reward;
  final bool canRedeem;
  final VoidCallback onRedeem;

  const _RewardCard({
    required this.reward,
    required this.canRedeem,
    required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: const BoxDecoration(
              color: AppColors.primaryExtraLight,
              borderRadius: AppRadius.kSmall,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.eco_rounded,
                  color: AppColors.primary,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  '${reward.cost}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            reward.title,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Text(
              reward.description,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: canRedeem ? onRedeem : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              ),
              child: Text('${reward.cost} Boncuk'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Native, honestly-illustrated wheel — a segmented ring drawn with
/// [CustomPaint] plus a plain list of the point values it can land on, not
/// a photo-realistic prop. See `LoyaltyNotifier.spinWheel`'s doc comment:
/// [kSpinWheelSegments] is a temporary placeholder value set, not real
/// prize-odds configuration.
class _SpinWheelCard extends StatelessWidget {
  final bool spinAvailable;
  final VoidCallback onSpin;

  const _SpinWheelCard({required this.spinAvailable, required this.onSpin});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Şans Çarkını Çevir 🎡',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Her gün çarkı çevir, boncuk kazanma şansı yakala!',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Günlük Hakkın',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      spinAvailable ? '1/1' : '0/1',
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              const SpinWheelIcon(size: 96),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final value in kSpinWheelSegments)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: AppRadius.kPill,
                  ),
                  child: Text(
                    '+$value',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: spinAvailable ? onSpin : null,
              icon: const Icon(Icons.casino_rounded, size: 18),
              label: Text(spinAvailable ? 'Çarkı Çevir' : 'Hakkın Doldu'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowToEarnCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Boncuk Nasıl Kazanılır?',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _EarnRow(
            icon: Icons.shopping_bag_outlined,
            title: 'Her siparişinde kazan!',
            description: '₺1 harcama = 1 Boncuk',
          ),
          const SizedBox(height: AppSpacing.md),
          const _EarnRow(
            icon: Icons.people_outline_rounded,
            title: 'Arkadaşını davet et',
            description: 'Her davette +50 Boncuk',
          ),
          const SizedBox(height: AppSpacing.md),
          const _EarnRow(
            icon: Icons.local_offer_outlined,
            title: 'Kampanyalara katıl',
            description: 'Ekstra boncuk fırsatlarını kaçırma!',
          ),
        ],
      ),
    );
  }
}

class _EarnRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _EarnRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                description,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
