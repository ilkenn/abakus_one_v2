import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The one section-title treatment every Home section uses — H.1.1's
/// "section titles should have consistent typography and spacing"
/// requirement made structural instead of just conventional (every section
/// previously hand-rolled its own `Text(...titleMedium.copyWith(bold))`,
/// which drifted easily).
///
/// H.2.1: dropped the small vertical accent bar this used to render next
/// to the title — physical review found it read as dashboard-style
/// decoration rather than editorial hierarchy. Typography (weight/size/
/// spacing) alone now carries the section-title identity.
class HomeSectionTitle extends StatelessWidget {
  final String title;

  const HomeSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        title,
        style: AppTypography.titleMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
