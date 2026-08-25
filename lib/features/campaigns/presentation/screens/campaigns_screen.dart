import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/models/campaign.dart';
import '../../domain/models/campaign_display.dart';
import '../providers/campaigns_provider.dart';
import 'campaign_detail_screen.dart';

/// Server-Authoritative Campaign Engine P8-B (2026-08-25) — the real
/// customer campaign listing. Sourced exclusively from
/// [activeCampaignsProvider] (`getCustomerActiveCampaigns`) — no mock
/// campaign source is reachable from here or anywhere downstream. Until a
/// future Admin creates a real campaign, this correctly shows the empty
/// state — never a fabricated fallback.
class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(activeCampaignsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kampanyalar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: campaignsAsync.when(
          loading: () =>
              const LoadingView(message: 'Kampanyalar yükleniyor...'),
          error: (error, stackTrace) => ErrorView(
            message: 'Kampanyalar şu anda yüklenemedi.',
            retryLabel: 'Tekrar Dene',
            onRetry: () => ref.invalidate(activeCampaignsProvider),
          ),
          data: (campaigns) {
            if (campaigns.isEmpty) {
              return const EmptyView(
                icon: Icons.campaign_outlined,
                message: 'Şu anda aktif kampanya bulunmuyor.',
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(activeCampaignsProvider.future),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xl),
                itemCount: campaigns.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.xl),
                itemBuilder: (context, index) {
                  final campaign = campaigns[index];
                  return _CampaignCard(
                    key: Key('campaignCard-${campaign.campaignId}'),
                    campaign: campaign,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({super.key, required this.campaign});

  final Campaign campaign;

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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: AppSpacing.sm),
              Text(
                campaign.schedule.validitySummary,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
