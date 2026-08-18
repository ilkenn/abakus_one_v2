import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../providers/profile_provider.dart';
import '../screens/loyalty_screen.dart';

/// Compact premium Boncuk/loyalty promo card — P.2 (2026-08-19). Deliberately
/// mirrors `features/home/presentation/widgets/boncuk_section.dart`'s
/// already-approved copy/visual treatment (same headline, support line, CTA
/// pill, bead-cluster decoration, gradient+`AppShadows.floating` surface) —
/// not imported from `features/home` (one feature importing another
/// feature's presentation widgets directly is forbidden, `CLAUDE.md` §3),
/// but deliberately kept visually identical rather than reinvented.
///
/// Like `BoncukSection`, this **never reads `loyaltyProvider`** — that
/// provider is unconditionally mock/seeded (balance, history, rewards all
/// hardcoded), so presenting any of it here as if it were the customer's
/// real state would be exactly the fabricated-data risk this redesign
/// keeps being asked to remove. There is no balance/progress value in
/// scope to accidentally show — only a static "get started" promo that
/// opens the real [LoyaltyScreen] (or, for a guest, [LoginScreen] first).
class ProfileLoyaltyCard extends ConsumerWidget {
  const ProfileLoyaltyCard({super.key});

  /// A small "bead string" — three overlapping circles standing in for
  /// Boncuk itself. Identical to `BoncukSection`'s, exactly 3 static
  /// decorative beads, never tied to a real balance.
  Widget _beadCluster() {
    Widget bead(double size, Color color, {double dx = 0, double dy = 0}) {
      return Positioned(
        left: dx,
        top: dy,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surface, width: 2),
            boxShadow: AppShadows.subtle,
          ),
        ),
      );
    }

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        children: [
          bead(30, AppColors.primaryExtraLight, dx: 0, dy: 20),
          bead(34, AppColors.primaryLight, dx: 16, dy: 4),
          bead(26, AppColors.primary, dx: 28, dy: 24),
        ],
      ),
    );
  }

  BoxDecoration get _premiumCardDecoration => BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.primaryExtraLight],
        ),
        borderRadius: AppRadius.kLarge,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.floating,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(
      profileProvider.select((profile) => profile != null),
    );

    return Semantics(
      button: true,
      label: isAuthenticated
          ? 'Boncuklarını biriktirmeye başla, detay için dokun'
          : 'Boncuk kazanmak için giriş yap',
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                isAuthenticated ? const LoyaltyScreen() : const LoginScreen(),
          ),
        ),
        child: Container(
          key: const Key('profileLoyaltyCard'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: _premiumCardDecoration,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _beadCluster(),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Boncuklarını Biriktirmeye Başla',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Her uygun siparişinle Boncuk kazan, ödüllere '
                      'yaklaş.',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: AppRadius.kPill,
                      ),
                      child: Text(
                        'Boncukları Keşfet',
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
