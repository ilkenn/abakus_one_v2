import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../data/mock_data.dart';

class CampaignCarousel extends StatefulWidget {
  final PageController pageController;

  const CampaignCarousel({super.key, required this.pageController});

  @override
  State<CampaignCarousel> createState() => _CampaignCarouselState();
}

class _CampaignCarouselState extends State<CampaignCarousel> {
  int _currentCampaignIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.pageController.addListener(_pageListener);
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_pageListener);
    super.dispose();
  }

  void _pageListener() {
    if (widget.pageController.hasClients) {
      final page = widget.pageController.page?.round() ?? 0;
      if (page != _currentCampaignIndex) {
        setState(() {
          _currentCampaignIndex = page;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: AppThemeConstants.campaignCarouselHeight,
          child: PageView.builder(
            itemCount: HomeMockData.campaigns.length,
            controller: widget.pageController,
            itemBuilder: (context, index) {
              final campaign = HomeMockData.campaigns[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: AppRadius.kLarge,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            campaign['title']!,
                            style: AppTypography.titleLarge.copyWith(
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            campaign['desc']!,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            HomeMockData.campaigns.length,
            (index) => AnimatedContainer(
              duration: AppThemeConstants.categoryTransitionDuration,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              height: 6,
              width: index == _currentCampaignIndex ? 16 : 6,
              decoration: BoxDecoration(
                color: index == _currentCampaignIndex
                    ? AppColors.primary
                    : AppColors.border,
                borderRadius: AppRadius.kPill,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
