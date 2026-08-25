import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/campaign.dart';
import '../../domain/models/campaign_display.dart';

/// Server-Authoritative Campaign Engine P8-B (2026-08-25) — full detail for
/// one real, server-sourced campaign: the offer itself, which commercial
/// channels it applies to, and its validity window. Every field is the
/// server-authoritative [Campaign] passed in by [CampaignsScreen] — this
/// screen invents nothing.
///
/// **Deliberately no "use this campaign" action.** Campaign selection at
/// checkout is explicitly out of scope this phase (P8-B is foundation
/// only — no `submit*Order.ts` channel accepts a `selectedCampaignId` yet)
/// — showing a CTA that implies otherwise would itself be a form of the
/// "no mock campaign catalog" problem this phase exists to fix. A future
/// checkout-integration phase adds the real selection UI, mirroring
/// `CatalogRewardCard`'s own pattern once it exists for campaigns.
class CampaignDetailScreen extends StatelessWidget {
  const CampaignDetailScreen({super.key, required this.campaign});

  final Campaign campaign;

  static const Map<String, String> _channelLabels = {
    'dineIn': 'Masa',
    'takeaway': 'Gel Al',
    'delivery': 'Paket Servis',
    'reservationPreorder': 'Rezervasyon',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kampanya Detayı'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.kLarge,
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.local_offer_rounded,
                      size: 64,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                campaign.title,
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.primaryExtraLight,
                  borderRadius: AppRadius.kPill,
                ),
                child: Text(
                  campaign.rule.summary,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                campaign.description,
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Divider(height: AppSpacing.xxl),
              const Text(
                'Geçerlilik ve Koşullar',
                style: AppTypography.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              _ConditionRow(
                icon: Icons.calendar_today_rounded,
                label: 'Geçerlilik:',
                value: campaign.schedule.validitySummary,
              ),
              if (campaign.minimumBasketMinorUnits != null)
                _ConditionRow(
                  icon: Icons.shopping_bag_outlined,
                  label: 'Minimum Sepet Tutarı:',
                  value:
                      '${(campaign.minimumBasketMinorUnits! / 100).toStringAsFixed(0)} TL',
                ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Nerede Geçerli?',
                style: AppTypography.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final channel in campaign.eligibleChannels)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryExtraLight,
                        borderRadius: AppRadius.kPill,
                      ),
                      child: Text(
                        _channelLabels[channel] ?? channel,
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
