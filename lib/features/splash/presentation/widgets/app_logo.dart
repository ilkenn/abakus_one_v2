import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';

/// The "Logo" leaf of the Phase 8 white-label hierarchy (`docs/decisions.md`
/// ADR-025: "Tenant → Brand → Theme → Application Identity → Logo →
/// Colors → ..."). **One deliberate exception** to this codebase's
/// otherwise-universal static `AppColors.*` usage: this widget reads
/// `Theme.of(context).colorScheme` instead, so it reflects
/// `resolvedAppThemeProvider`'s tenant color palette when one is set —
/// every other screen in this codebase still reads `AppColors.*`
/// directly and does **not** pick up a tenant's brand color yet
/// (`build_theme_from_brand_presentation.dart`'s own doc comment records
/// this as an explicit, honestly-disclosed scope boundary, not an
/// oversight). No real logo *image* renders here regardless — no
/// `image_picker`/media-resolution dependency exists in this codebase
/// to turn a `BrandAssetSet.logoRef` into a displayable image (mirrors
/// `CustomerPhoto.photoRef`'s same opaque-reference limitation,
/// Phase 6 ADR-023 Decision 5) — only the tint color is tenant-aware.
class AppLogoWidget extends StatelessWidget {
  const AppLogoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    const double logoDiameter = AppSpacing.xxxl * 2;
    const double innerIconSize = AppSpacing.xxxl - AppSpacing.sm;
    final colorScheme = Theme.of(context).colorScheme;

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
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: AppRadius.kPill,
          ),
          child: Center(
            child: Icon(
              Icons.restaurant_rounded,
              color: colorScheme.onPrimary,
              size: innerIconSize,
            ),
          ),
        ),
      ),
    );
  }
}
