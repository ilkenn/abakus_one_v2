import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Title block for a labeled section within a screen: a title, an optional
/// helper subtitle, and a "Zorunlu"/"İsteğe bağlı" pill reflecting
/// [isRequired] — always shown, so required vs. optional is scannable at a
/// glance without reading the subtitle text.
///
/// Shared across features (Bowl Builder's ingredient steps and Product
/// Detail's modifier groups both need this exact "group name + required
/// badge + helper text" pattern) rather than owned by whichever feature
/// needed it first.
class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isRequired;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.isRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: isRequired
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.surfaceVariant,
                borderRadius: AppRadius.kPill,
              ),
              child: Text(
                isRequired ? 'Zorunlu' : 'İsteğe bağlı',
                style: AppTypography.bodySmall.copyWith(
                  color:
                      isRequired ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
