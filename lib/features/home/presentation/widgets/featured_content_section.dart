import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../campaigns/presentation/providers/campaigns_provider.dart';
import '../../../campaigns/presentation/screens/campaigns_screen.dart';
import 'home_section_title.dart';

/// Real content only — new products, chef's picks, seasonal items, or
/// active campaigns (sourced from the real [activeCampaignsProvider],
/// never fabricated Home-only mock text). Renders nothing at all when there
/// is no real content to show, per the explicit "do not display fake data
/// just to fill space" requirement.
///
/// Server-Authoritative Campaign Engine P8-B (2026-08-25) — updated to the
/// real `getCustomerActiveCampaigns`-backed provider (was the mock
/// `campaignsProvider`). Still deliberately omitted from `HomeScreen`'s own
/// tree (see that screen's own doc comment) — kept building only per the
/// no-silent-deletion rule.
class FeaturedContentSection extends ConsumerWidget {
  const FeaturedContentSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCampaigns =
        ref.watch(activeCampaignsProvider).valueOrNull ?? const [];

    if (activeCampaigns.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionTitle('Öne Çıkanlar'),
        SizedBox(
          height: 132,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: activeCampaigns.length,
            itemBuilder: (context, index) {
              final campaign = activeCampaigns[index];
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: Semantics(
                  button: true,
                  label: '${campaign.title}, ${campaign.description}',
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CampaignsScreen(),
                      ),
                    ),
                    child: Container(
                      width: 260,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.primaryExtraLight,
                        borderRadius: AppRadius.kLarge,
                        border: Border.all(color: AppColors.border),
                        boxShadow: AppShadows.card,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            campaign.title,
                            style: AppTypography.labelLarge.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            campaign.description,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
