import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../navigation/presentation/providers/navigation_provider.dart';
import '../../../takeaway/presentation/screens/takeaway_branch_selection_screen.dart';
import '../../domain/models/loyalty_reward.dart';
import '../providers/loyalty_providers.dart';

/// Boncuk Loyalty Program P7-D (2026-08-24) — full detail for one reward:
/// exact Boncuk cost, which real canonical products it covers, and which
/// commercial channels it can actually be redeemed on. Every field is the
/// server-authoritative [LoyaltyReward] passed in by [RewardsScreen] — this
/// screen invents nothing.
///
/// **The CTA never creates a standalone voucher/claim.** Tapping it routes
/// the customer into the real, existing checkout flow for one of the
/// reward's eligible channels — the SAME [CatalogRewardCard] already wired
/// into that checkout is what actually lets them select the reward, once
/// an eligible product is in their cart. This screen only gets them there.
class RewardDetailScreen extends ConsumerWidget {
  const RewardDetailScreen({super.key, required this.reward});

  final LoyaltyReward reward;

  /// The commercial channels THIS APP can currently actually route a
  /// customer into ordering through — a UI-capability/navigation concern,
  /// distinct from the server's own open `eligibleChannels` vocabulary
  /// (never hardcoded as a validation/eligibility rule anywhere — the
  /// server alone decides whether a redemption is valid). `dineIn` is
  /// deliberately excluded: dine-in order creation has no server-
  /// authoritative pipeline yet (P7-D), so a reward configured for it
  /// cannot be shown as usable there, even if the server-side vocabulary
  /// technically lists it.
  static const Map<String, String> _appRoutableChannelLabels = {
    'takeaway': 'Gel Al',
    'delivery': 'Paket Servis',
    'reservationPreorder': 'Rezervasyon',
  };

  static const Map<String, String> _allChannelLabels = {
    'dineIn': 'Masa',
    'takeaway': 'Gel Al',
    'delivery': 'Paket Servis',
    'reservationPreorder': 'Rezervasyon',
  };

  void _routeToChannel(BuildContext context, WidgetRef ref, String channel) {
    // Pop back to the root of the navigation stack first (this screen may
    // be several `Navigator.push`es deep — Boncuklarım → Ödüller → this
    // detail screen), then route into the real checkout entry point for
    // the chosen channel, mirroring `HomeScreen`'s own `OrderModeSection`
    // navigation exactly (the same targets a customer reaches from Home).
    Navigator.of(context).popUntil((route) => route.isFirst);
    switch (channel) {
      case 'delivery':
        ref.read(navigationProvider.notifier).selectTab(AppTab.menu);
      case 'takeaway':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const TakeawayBranchSelectionScreen(),
          ),
        );
      case 'reservationPreorder':
        context.push(AppRoutes.reservationPrefix);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(menuProductsProvider);
    final snapshotAsync = ref.watch(loyaltySnapshotProvider);
    final spendableBalance = snapshotAsync.valueOrNull?.spendableBalance;
    final canAfford =
        spendableBalance != null && spendableBalance >= reward.boncukCost;

    final eligibleProducts = [
      for (final productId in reward.eligibleProductIds)
        catalog.where((p) => p.id == productId).firstOrNull,
    ].whereType<MenuProduct>().toList(growable: false);

    final usableChannels = reward.eligibleChannels
        .where(_appRoutableChannelLabels.containsKey)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ödül Detayı'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: const BoxDecoration(
                  color: AppColors.primaryExtraLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.redeem_rounded,
                    size: 40, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              reward.title,
              style: AppTypography.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              reward.description,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppCard(
              key: const Key('rewardDetailCostCard'),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Gerekli Boncuk',
                      style: AppTypography.titleMedium),
                  Text(
                    '${reward.boncukCost} Boncuk',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (eligibleProducts.isNotEmpty) ...[
              const Text('Uygun Ürünler', style: AppTypography.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < eligibleProducts.length; i++) ...[
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(eligibleProducts[i].name,
                                  style: AppTypography.bodyMedium),
                            ),
                          ],
                        ),
                      ),
                      if (i != eligibleProducts.length - 1)
                        const Divider(height: 1, color: AppColors.border),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            const Text('Nerede Kullanılabilir?',
                style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final channel in reward.eligibleChannels)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: _appRoutableChannelLabels.containsKey(channel)
                          ? AppColors.primaryExtraLight
                          : AppColors.surfaceVariant,
                      borderRadius: AppRadius.kPill,
                    ),
                    child: Text(
                      _allChannelLabels[channel] ?? channel,
                      style: AppTypography.labelLarge.copyWith(
                        color: _appRoutableChannelLabels.containsKey(channel)
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            if (!canAfford && spendableBalance != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: AppRadius.kMedium,
                ),
                child: Text(
                  'Bu ödülü kullanmak için ${reward.boncukCost - spendableBalance} '
                  'Boncuk daha kazanmalısın.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (usableChannels.isEmpty)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: AppRadius.kMedium,
                ),
                child: Text(
                  'Bu ödül şu anda uygulama üzerinden kullanılamıyor.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              )
            else if (usableChannels.length == 1)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('rewardDetailUseCta'),
                  onPressed: canAfford
                      ? () =>
                          _routeToChannel(context, ref, usableChannels.first)
                      : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.kExtraLarge),
                  ),
                  child: Text(
                    canAfford
                        ? '${_appRoutableChannelLabels[usableChannels.first]} ile Kullan'
                        : 'Yeterli Boncuk Yok',
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('rewardDetailUseCta'),
                  onPressed: canAfford
                      ? () => _showChannelPicker(context, ref, usableChannels)
                      : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.kExtraLarge),
                  ),
                  child: Text(
                      canAfford ? 'Bu Ödülü Kullan' : 'Yeterli Boncuk Yok'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showChannelPicker(
    BuildContext context,
    WidgetRef ref,
    List<String> usableChannels,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('Nerede kullanmak istersin?',
                  style: AppTypography.titleMedium),
            ),
            for (final channel in usableChannels)
              ListTile(
                key: Key('rewardDetailChannelOption-$channel'),
                leading: const Icon(Icons.arrow_forward_rounded,
                    color: AppColors.primary),
                title: Text(_appRoutableChannelLabels[channel] ?? channel),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _routeToChannel(context, ref, channel);
                },
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}
