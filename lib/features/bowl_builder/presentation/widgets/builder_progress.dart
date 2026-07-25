import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// Segmented progress bar across the top of the Bowl Builder flow — one
/// segment per step, filled up to and including [currentIndex]. Each
/// segment animates its own fill instead of snapping instantly, so
/// stepping forward/back reads as motion, not a jump cut.
class BuilderProgress extends StatelessWidget {
  final int currentIndex;
  final int totalSteps;

  const BuilderProgress({
    super.key,
    required this.currentIndex,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (index) {
        final isFilled = index <= currentIndex;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.only(
              right: index == totalSteps - 1 ? 0 : AppSpacing.xs,
            ),
            height: 6,
            decoration: BoxDecoration(
              color: isFilled ? AppColors.primary : AppColors.border,
              borderRadius: AppRadius.kPill,
            ),
          ),
        );
      }),
    );
  }
}
