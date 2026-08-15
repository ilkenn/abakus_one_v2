import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/presentation/providers/loyalty_provider.dart';

/// Compact loyalty entry point: current balance, one short message, a tap
/// target for the full Loyalty screen — deliberately smaller/quieter than
/// [BuildBowlBanner] (a single row, no image, no gradient). The richer
/// spin-wheel/daily-tasks/campaign-list detail lives behind that entry
/// point already, not duplicated here.
class BoncukSection extends ConsumerWidget {
  final VoidCallback onTap;
  final VoidCallback onLoginTap;

  const BoncukSection({
    super.key,
    required this.onTap,
    required this.onLoginTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(
      authProvider.select((state) => state.isAuthenticated),
    );

    if (!isAuthenticated) {
      return Semantics(
        button: true,
        label: 'Boncuk kazanmak için giriş yap',
        child: GestureDetector(
          onTap: onLoginTap,
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.eco_rounded,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Boncuk kazanmaya başla',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final balance = ref.watch(
      loyaltyProvider.select((state) => state.currentBalance),
    );

    return Semantics(
      button: true,
      label: '$balance Boncuk, detay için dokun',
      child: GestureDetector(
        onTap: onTap,
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.eco_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$balance Boncuk',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'Her siparişte biraz daha kazan.',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
