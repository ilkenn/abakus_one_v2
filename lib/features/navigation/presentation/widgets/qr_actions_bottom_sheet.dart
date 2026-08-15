import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Shown when the bottom navigation's center QR action is tapped — the user
/// picks an action first, the camera never opens automatically. Minimal,
/// premium: a drag handle, a title, and exactly two tappable actions.
class QrActionsBottomSheet extends StatelessWidget {
  final VoidCallback onBoncukKazan;
  final VoidCallback onMasadaSiparisVer;

  const QrActionsBottomSheet({
    super.key,
    required this.onBoncukKazan,
    required this.onMasadaSiparisVer,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.border,
                  borderRadius: AppRadius.kPill,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'QR İşlemleri',
              style: AppTypography.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            _QrActionTile(
              icon: Icons.eco_rounded,
              title: 'Boncuk Kazan',
              subtitle: 'QR okut, sipariş ver ve boncuk kazan.',
              onTap: onBoncukKazan,
            ),
            const SizedBox(height: AppSpacing.sm),
            _QrActionTile(
              icon: Icons.table_restaurant_rounded,
              title: 'Masada Sipariş Ver',
              subtitle: 'Masandaki QR kodu okut ve sipariş ver.',
              onTap: onMasadaSiparisVer,
            ),
          ],
        ),
      ),
    );
  }
}

class _QrActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QrActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: Material(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.kMedium,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.kMedium,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryExtraLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
