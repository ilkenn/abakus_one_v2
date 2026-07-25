import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';

class AppLogoWidget extends StatelessWidget {
  const AppLogoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    const double logoDiameter = AppSpacing.xxxl * 2;
    const double innerIconSize = AppSpacing.xxxl - AppSpacing.sm;

    return Container(
      width: logoDiameter,
      height: logoDiameter,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: AppRadius.kPill,
          ),
          child: const Center(
            child: Icon(
              Icons.restaurant_rounded,
              color: AppColors.onPrimary,
              size: innerIconSize,
            ),
          ),
        ),
      ),
    );
  }
}
