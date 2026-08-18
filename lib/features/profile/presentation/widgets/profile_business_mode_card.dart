import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../admin/presentation/screens/admin_shell_screen.dart';

/// "İşletme Moduna Geç" — P.3 (2026-08-19). A mode switch, not another
/// customer settings row: solid `AppColors.primary` background (rather
/// than this screen's cream/sage cards) so it reads as leaving customer
/// Profile entirely, while staying within the app's own palette.
///
/// The caller (`ProfileScreen`) is solely responsible for only mounting
/// this widget when `actorSessionProvider?.roles.isNotEmpty == true` —
/// this widget itself does not re-check authorization, matching the
/// locked P.3 rule that unauthorized/guest customers must never see this
/// card at all (not even a disabled/hidden variant of it). Tapping always
/// goes straight to the real [AdminShellScreen] — Profile no longer routes
/// to `StaffSignInScreen` from here (that fallback belonged to the old
/// "Yönetici Paneli" row, which this replaces).
class ProfileBusinessModeCard extends StatelessWidget {
  const ProfileBusinessModeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'İşletme Moduna Geç, personel ve yönetim araçlarına geç',
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AdminShellScreen()),
        ),
        child: Container(
          key: const Key('profileBusinessModeCard'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: AppRadius.kLarge,
            boxShadow: AppShadows.floating,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'İşletme Moduna Geç',
                      style: AppTypography.bodyLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Personel ve yönetim araçlarına geç',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
