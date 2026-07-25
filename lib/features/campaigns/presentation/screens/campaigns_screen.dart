import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../domain/models/campaign_model.dart';
import '../providers/campaigns_provider.dart';
import 'campaign_detail_screen.dart';

class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(campaignsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kampanyalar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: campaigns.isEmpty
            ? Center(
                child: Text(
                  'Şu anda aktif kampanya bulunmuyor.',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.xl),
                itemCount: campaigns.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.xl),
                itemBuilder: (context, index) {
                  final campaign = campaigns[index];
                  return _CampaignCard(campaign: campaign);
                },
              ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  final CampaignModel campaign;

  const _CampaignCard({required this.campaign});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.kLarge,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CampaignDetailScreen(campaign: campaign),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.kLarge,
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Container(
                height: 180,
                color: AppColors.surfaceVariant,
                child: const Center(
                  child: Icon(
                    Icons.campaign_outlined,
                    size: 48,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campaign.title,
                    style: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    campaign.description,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (!campaign.isActive) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Süresi Dolmuş',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
