import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Shown by `AdminShellScreen` when a previously-active `ActorSession`
/// becomes invalid — [ActorSession.isExpired] or [ActorSession.revoked]
/// — distinct from [AdminUnauthorizedScreen] (which is for "never signed
/// in at all"). Phase 6A (`docs/decisions.md` ADR-023).
class AdminSessionExpiredScreen extends StatelessWidget {
  const AdminSessionExpiredScreen({super.key, this.onSignInAgain});

  final VoidCallback? onSignInAgain;

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
                const Icon(Icons.timer_off_outlined,
                    size: 56, color: AppColors.textSecondary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Oturumunuzun süresi doldu veya iptal edildi.',
                  style: AppTypography.bodyLarge
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                if (onSignInAgain != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: onSignInAgain,
                    child: const Text('Tekrar Giriş Yap'),
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
