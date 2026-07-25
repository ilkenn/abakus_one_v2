import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../features/profile/domain/models/loyalty_campaign_model.dart';

/// Shown on both the Loyalty screen and Home, so it lives here per the
/// architecture bible's shared-widget-promotion rule.
class LoyaltyCampaignCard extends StatelessWidget {
  final LoyaltyCampaignModel campaign;

  const LoyaltyCampaignCard({super.key, required this.campaign});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.primaryExtraLight,
        borderRadius: AppRadius.kMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            campaign.title,
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            campaign.description,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                campaign.actionLabel,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.primary,
                size: 16,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
