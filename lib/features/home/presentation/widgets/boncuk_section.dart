import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'home_section_title.dart';

/// Compact loyalty entry point — deliberately smaller/quieter than
/// [BuildBowlBanner] (a single row, no image, no gradient). The richer
/// spin-wheel/daily-tasks/campaign-list detail lives behind the tap target
/// (the full Loyalty screen) already, not duplicated here.
///
/// H.1.1 loyalty mock-data correction: this widget deliberately never
/// reads `loyaltyProvider` — that provider is unconditionally mock/seeded
/// in every environment (`docs/decisions.md` ADR-022; no
/// `AppEnvironment`/dev-only gate exists anywhere in its own file, verified
/// by inspection, not assumed), so its balance/progress must never be
/// presented on Home as if it were real customer state. The authenticated
/// branch below previously showed `$balance Boncuk` + a tier-progress bar
/// derived straight from that mock seed data — replaced with a premium
/// "not started yet" state instead, still opening the real Loyalty screen
/// on tap.
///
/// H.2.3: the guest (unauthenticated) branch previously kept its original
/// H.1-era plain settings-row layout (bare icon + "Boncuk kazanmaya başla"
/// + chevron) on the theory that it was never showing fabricated data, so
/// it didn't need the H.2.1/H.2.2 premium-card treatment. Physical review
/// of H.2.2 was done signed out, so that settings-row was exactly what
/// kept showing up as "still not fixed" — the *visual* problem was never
/// guest-specific. Both branches now share one `_PremiumLoyaltyCard`
/// presentation; only the tap destination and its accessibility label
/// differ (guest → sign in first, authenticated → straight to Loyalty).
class BoncukSection extends ConsumerWidget {
  final VoidCallback onTap;
  final VoidCallback onLoginTap;

  const BoncukSection({
    super.key,
    required this.onTap,
    required this.onLoginTap,
  });

  /// A small "bead string" — three overlapping circles standing in for
  /// Boncuk itself, rather than a generic leaf/eco icon. H.2: the previous
  /// single icon badge read as a plain utility-row glyph; this gives the
  /// section a visual specific to the loyalty currency it represents,
  /// without fabricating any count (exactly 3 static decorative beads,
  /// never tied to a real balance).
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

  /// H.2.2: a subtle sage-tinted gradient + the stronger `floating`
  /// shadow, distinct from every other plain-white card on Home — this is
  /// the section that most needs to read as a premium loyalty promo, not
  /// a settings row, so it gets a touch more visual depth than its
  /// neighbors.
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
      authProvider.select((state) => state.isAuthenticated),
    );

    // Deliberately no `ref.watch(loyaltyProvider)` here — see class doc
    // comment. Nothing below is derived from it; there is no balance or
    // progress value in scope to accidentally fabricate. Same premium
    // card for both auth states (H.2.3) — only the tap destination and
    // its accessibility label differ.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionTitle('Boncuk Kulübü'),
        Semantics(
          button: true,
          label: isAuthenticated
              ? 'Boncuklarını biriktirmeye başla, detay için dokun'
              : 'Boncuk kazanmak için giriş yap',
          child: GestureDetector(
            onTap: isAuthenticated ? onTap : onLoginTap,
            child: Container(
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
                        // Compact real CTA — H.2.1: this section used to
                        // read as a plain settings row (icon + text +
                        // chevron); a visible loyalty-branded button gives
                        // it the weight of an actual promo card instead.
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
        ),
      ],
    );
  }
}
