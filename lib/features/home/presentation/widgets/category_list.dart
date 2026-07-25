import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../data/mock_data.dart';

class CategoryList extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onCategorySelected;

  const CategoryList({
    super.key,
    required this.selectedIndex,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppThemeConstants.categoryListHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: HomeMockData.categories.length,
        itemBuilder: (context, index) {
          final isSelected = index == selectedIndex;
          return GestureDetector(
            onTap: () => onCategorySelected(index),
            child: AnimatedContainer(
              duration: AppThemeConstants.categoryTransitionDuration,
              curve: Curves.easeInOut,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              decoration: BoxDecoration(
                color:
                    isSelected ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: AppRadius.kMedium,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: AppThemeConstants.categoryTransitionDuration,
                  curve: Curves.easeInOut,
                  style: AppTypography.labelLarge.copyWith(
                    color: isSelected
                        ? AppColors.onPrimary
                        : AppColors.textPrimary,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  child: Text(HomeMockData.categories[index]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
