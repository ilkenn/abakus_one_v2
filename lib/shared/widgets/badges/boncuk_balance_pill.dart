import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../features/profile/presentation/providers/loyalty_provider.dart';

/// A Boncuk (loyalty point) balance pill. Reads [loyaltyProvider] directly
/// so any screen that mounts it shows the same balance without threading it
/// through as a parameter.
///
/// **Stale-comment correction (customer-side closure audit, 2026-08-26)**:
/// this doc comment previously claimed the pill is "shown in the top bar of
/// most screens... used by 5+ features." That was never wired up — its only
/// real caller today is the orphaned, zero-reference
/// `features/profile/presentation/screens/loyalty_screen.dart` (the old
/// mock balance/tiers/wheel screen `CLAUDE.md` §3 documents as superseded
/// by `features/loyalty/`). [loyaltyProvider] itself is also unconditionally
/// seeded/mock — every other Boncuk-showing widget in this codebase
/// (`boncuk_section.dart`, `profile_loyalty_card.dart`,
/// `profile_quick_actions.dart`, `home_top_bar.dart`) deliberately avoids
/// both this widget and that provider for exactly that reason, reading the
/// real server-authoritative snapshot instead. Left in place, unreachable
/// from production, pending a decision on whether to wire it to the real
/// loyalty snapshot or remove it — not touched further by this audit.
class BoncukBalancePill extends ConsumerWidget {
  const BoncukBalancePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(loyaltyProvider).currentBalance;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.primaryExtraLight,
        borderRadius: AppRadius.kPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.eco_rounded, color: AppColors.primary, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$balance',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                  height: 1.0,
                ),
              ),
              Text(
                'Boncuk',
                style: AppTypography.caption.copyWith(
                  color: AppColors.primary,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
