import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The dark Abaküs-green left operational navigation strip shared by every
/// POS screen — AP-3 continuation. Existing design tokens only.
class PosOperationalRail extends StatelessWidget {
  const PosOperationalRail({super.key, this.onBack});

  final VoidCallback? onBack;

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
