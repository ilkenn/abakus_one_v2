import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../domain/models/campaign_model.dart';
import '../providers/campaigns_provider.dart';

class CampaignDetailScreen extends ConsumerWidget {
  final CampaignModel campaign;

  const CampaignDetailScreen({super.key, required this.campaign});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freshCampaign = ref
        .watch(campaignsProvider)
        .firstWhere((c) => c.id == campaign.id, orElse: () => campaign);

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
                freshCampaign.title,
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                freshCampaign.description,
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Divider(height: AppSpacing.xxl),
              Text(
                'Kampanya Koşulları ve Detayları',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _buildConditionRow(
                Icons.calendar_today_rounded,
                'Son Geçerlilik Tarihi:',
                freshCampaign.endDate,
              ),
              _buildConditionRow(
                Icons.shopping_bag_outlined,
                'Minimum Sepet Tutarı:',
                freshCampaign.minimumOrderAmount > 0
                    ? '${freshCampaign.minimumOrderAmount.toStringAsFixed(0)} TL'
                    : 'Koşul Yok',
              ),
              _buildConditionRow(
                Icons.vpn_key_rounded,
                'Kupon Kodu:',
                freshCampaign.couponCode,
              ),
              _buildConditionRow(
                Icons.check_circle_outline_rounded,
                'Durum:',
                freshCampaign.isActive ? 'Aktif' : 'Süresi Dolmuş',
              ),
              const SizedBox(height: AppSpacing.xxl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      (!freshCampaign.isActive || freshCampaign.isClaimed)
                          ? null
                          : () {
                              ref
                                  .read(campaignsProvider.notifier)
                                  .claimCoupon(freshCampaign.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${freshCampaign.couponCode} kuponu hesabınıza eklendi!',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                  ),
                  child: Text(
                    freshCampaign.isClaimed
                        ? 'Kupon Hesabınızda'
                        : 'Kuponu Hesaba Ekle',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConditionRow(IconData icon, String label, String value) {
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
