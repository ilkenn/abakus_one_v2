import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// An honest "not built yet" placeholder for an Admin Shell section that
/// has no real screen behind it — "if a target module has no real admin
/// screen, report it... do not fabricate complete management
/// capability" (Phase 6, `docs/decisions.md` ADR-023). Never presented
/// as a loading state or an empty-data state — [reason] always names
/// specifically what's missing.
class AdminComingSoonView extends StatelessWidget {
  const AdminComingSoonView({
    super.key,
    required this.title,
    required this.reason,
  });

  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction_outlined,
                    size: 48, color: AppColors.textSecondary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  reason,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
