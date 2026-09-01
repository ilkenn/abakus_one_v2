import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The dark Abaküs-green left operational navigation strip shared by every
/// POS screen — AP-3 continuation. Existing design tokens only.
class PosOperationalRail extends StatelessWidget {
  const PosOperationalRail({super.key, this.onBack, this.onCashRegister});

  final VoidCallback? onBack;

  /// AP-4 Wave D — `null` hides the button entirely (never a disabled
  /// no-op) rather than showing an action a caller hasn't wired up yet.
  final VoidCallback? onCashRegister;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          const Icon(Icons.storefront_rounded,
              color: AppColors.onPrimary, size: 32),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'POS',
            style:
                AppTypography.labelLarge.copyWith(color: AppColors.onPrimary),
          ),
          const Spacer(),
          if (onCashRegister != null)
            IconButton(
              icon: const Icon(Icons.point_of_sale_rounded,
                  color: AppColors.onPrimary),
              tooltip: 'Kasa',
              onPressed: onCashRegister,
            ),
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.onPrimary),
            tooltip: 'Geri',
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
