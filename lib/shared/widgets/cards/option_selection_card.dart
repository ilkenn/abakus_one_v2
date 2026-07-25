import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A single selectable option tile — one radio-style or checkbox-style
/// choice within a modifier/ingredient group.
///
/// Shared across features (Bowl Builder's ingredient steps and Product
/// Detail's modifier groups both need exactly this interaction) per the
/// architecture bible's rule that a widget used by two or more features
/// belongs in `shared/widgets`, not owned by whichever feature happened to
/// need it first.
class OptionSelectionCard extends StatelessWidget {
  final String name;
  final double extraPrice;
  final bool isSelected;
  final VoidCallback onTap;

  /// Shows an explicit "Ücretsiz" tag when [extraPrice] is 0, instead of
  /// just omitting a price tag. Off by default so existing call sites (where
  /// "no price shown" already reads as free) don't gain new text; Bowl
  /// Builder opts in so its free-vs-premium distinction is unambiguous.
  final bool showFreeTag;

  const OptionSelectionCard({
    super.key,
    required this.name,
    required this.extraPrice,
    required this.isSelected,
    required this.onTap,
    this.showFreeTag = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.kMedium,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.08)
                : AppColors.surface,
            borderRadius: AppRadius.kMedium,
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  name,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (extraPrice > 0)
                Text(
                  '+${extraPrice.toStringAsFixed(0)} TL',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (showFreeTag)
                Text(
                  'Ücretsiz',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
