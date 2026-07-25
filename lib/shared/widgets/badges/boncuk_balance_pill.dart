import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../features/profile/presentation/providers/loyalty_provider.dart';

/// The Boncuk (loyalty point) balance pill shown in the top bar of most
/// screens (Home, Menu, Cart, Checkout, Order Tracking, Loyalty, Product
/// Detail, ...). Reads [loyaltyProvider] directly so every screen shows the
/// same live balance without threading it through as a parameter.
///
/// Shared because it's used by 5+ features — per the architecture bible's
/// rule, a widget used by two or more features belongs in `shared/widgets`,
/// not owned by whichever screen needed it first.
class BoncukBalancePill extends ConsumerWidget {
  const BoncukBalancePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(loyaltyProvider).currentBalance;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.primaryExtraLight,
        borderRadius: AppRadius.kPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.eco_rounded, color: AppColors.primary, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$balance',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                  height: 1.0,
                ),
              ),
              Text(
                'Boncuk',
                style: AppTypography.caption.copyWith(
                  color: AppColors.primary,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
