import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Shown by `AdminShellScreen` when there is no active session at all —
/// distinct from `RoleGate`'s inline per-destination denial (which
/// assumes a session exists but lacks a specific permission). Phase 6A
/// (`docs/decisions.md` ADR-023).
class AdminUnauthorizedScreen extends StatelessWidget {
  const AdminUnauthorizedScreen({super.key, this.onSignIn});

  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_person_outlined,
                    size: 56, color: AppColors.textSecondary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Bu alana erişmek için personel/yönetici girişi '
                  'yapmalısınız.',
                  style: AppTypography.bodyLarge
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                if (onSignIn != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: onSignIn,
                    child: const Text('Giriş Yap'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
