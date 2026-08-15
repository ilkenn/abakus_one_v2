import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/bowl_builder_category.dart';
import '../../domain/models/bowl_builder_step.dart';

/// Horizontal, always-jumpable category selector — the v2 replacement for
/// the old linear "Adım N/9" wizard. Tapping any chip calls
/// `notifier.goToStep(...)` directly (reusing the existing navigation state,
/// no duplicate selection state of its own), so the customer can move from
/// Protein straight to Soslar with nothing in between.
///
/// [currentStep] is the screen's `state.currentStep` as-is, including
/// [BowlBuilderStep.summary] — no chip's id ever equals `'summary'`, so on
/// the review step every chip correctly renders unselected rather than one
/// of them looking (wrongly) active.
class BowlBuilderCategorySelector extends StatelessWidget {
  final List<BowlBuilderCategory> categories;
  final BowlBuilderStep currentStep;
  final ValueChanged<BowlBuilderStep> onCategorySelected;

  const BowlBuilderCategorySelector({
    super.key,
    required this.categories,
    required this.currentStep,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        key: const Key('categorySelectorListView'),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final category = categories[index];
          final step = BowlBuilderStep.values.byName(category.id);
          final isSelected = step == currentStep;
          return _CategoryChip(
            label: category.displayName ?? category.name,
            isSelected: isSelected,
            onTap: () => onCategorySelected(step),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Material(
        color: isSelected ? AppColors.background : Colors.transparent,
        borderRadius: AppRadius.kPill,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.kPill,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 1.5 : 1,
              ),
              borderRadius: AppRadius.kPill,
            ),
            child: Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
