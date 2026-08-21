import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/loyalty_account_snapshot.dart';

/// Formats a TL amount for display — whole TL amounts render with no
/// decimals ("50 TL"); an amount with a genuine fractional part renders
/// with exactly two decimals ("0.50 TL"). Needed because
/// `redemptionValueMinorUnitsPerBoncuk` is now a genuinely arbitrary
/// server-configured value (Configurable Loyalty Economics, 2026-08-24) —
/// a fixed `toStringAsFixed(0)` would silently round a sub-1-TL value
/// (e.g. `50` minor units = "0.50 TL") down to "0".
String _formatTl(double valueTl) {
  final isWhole = valueTl == valueTl.roundToDouble();
  return isWhole ? valueTl.toStringAsFixed(0) : valueTl.toStringAsFixed(2);
}

/// P3A Visual Polish (2026-08-24) — the Boncuklarım hero: the customer's
/// real, current spendable balance, prominently large, as the card's sole
/// visual focal point. Deliberately compact (a sage/olive gradient card,
/// not a tall white `AppCard` with a leading icon and generous top/bottom
/// padding, per the polish pass's own "reduce vertical height significantly"
/// requirement) — never renders a fabricated number; [snapshot] is always
/// the resolved, real `getCustomerLoyaltySnapshot` response by the time this
/// widget builds (the screen owns the loading/error branching).
class AbacusCard extends StatelessWidget {
  const AbacusCard({super.key, required this.snapshot});

  final LoyaltyAccountSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    // BR-LOYALTY-005 — cash-like redemption rate, server-authoritative and
    // configurable per organization (Configurable Loyalty Economics,
    // 2026-08-24 — `snapshot.redemptionValueMinorUnitsPerBoncuk`, never a
    // Flutter constant). Informational only, per the locked product copy:
    // never implies the full balance can always be spent on one order (the
    // real `maxRedemptionBasisPoints` cap applies once checkout redemption
    // ships).
    final redemptionValueTl = snapshot.redemptionValueMinorUnitsPerBoncuk / 100;
    final approxTlValue = snapshot.spendableBalance * redemptionValueTl;

    return Container(
      key: const Key('abacusCard'),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primary],
        ),
        borderRadius: AppRadius.kExtraLarge,
        boxShadow: AppShadows.floating,
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -18,
            top: -22,
            child: _OrganicBeadMotif(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Boncuklarım',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  label: '${snapshot.spendableBalance} Boncuk bakiyen',
                  excludeSemantics: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${snapshot.spendableBalance}',
                        key: const Key('abacusCardBalance'),
                        style: AppTypography.displayLarge.copyWith(
                          color: Colors.white,
                          fontSize: 44,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Boncuk',
                          style: AppTypography.titleMedium.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ExcludeSemantics(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '1 Boncuk = ${_formatTl(redemptionValueTl)} TL',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      if (snapshot.spendableBalance > 0) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          child: Text(
                            '·',
                            style: AppTypography.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        Text(
                          '≈ ${_formatTl(approxTlValue)} TL değerinde',
                          key: const Key('abacusCardApproxValue'),
                          style: AppTypography.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (snapshot.boncukDebt > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  _DebtExplainer(debtBoncuk: snapshot.boncukDebt),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A subtle, purely decorative abacus/organic motif — three overlapping
/// translucent circles standing in for Boncuk beads, mirroring
/// `ProfileLoyaltyCard`'s own established "bead cluster" technique (Flutter
/// shapes only, no image asset, never tied to a real balance value).
/// Positioned outside the card's content flow (absolutely, via the parent
/// `Stack`) so it adds zero height to the hero — purely textural.
class _OrganicBeadMotif extends StatelessWidget {
  const _OrganicBeadMotif();

  @override
  Widget build(BuildContext context) {
    Widget bead(double size, double opacity, {double dx = 0, double dy = 0}) {
      return Positioned(
        left: dx,
        top: dy,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    return ExcludeSemantics(
      child: SizedBox(
        width: 120,
        height: 120,
        child: Stack(
          children: [
            bead(70, 0.10, dx: 30, dy: 10),
            bead(48, 0.14, dx: 4, dy: 46),
            bead(34, 0.18, dx: 66, dy: 62),
          ],
        ),
      ),
    );
  }
}

/// Calm, non-alarming explanation for why new earning may temporarily not
/// increase spendable balance — never "borçlusun"/legalistic wording, per
/// the locked product copy. Balance itself is never shown negative; the
/// hero above already only ever renders [LoyaltyAccountSnapshot.spendableBalance],
/// which is guaranteed `>= 0` server-side (BR-LOYALTY-014). Styled as a
/// translucent white chip against the hero's gradient (P3A Visual Polish),
/// replacing the flat `AppColors.surfaceVariant` block that only worked on
/// a light card background.
class _DebtExplainer extends StatelessWidget {
  const _DebtExplainer({required this.debtBoncuk});

  final int debtBoncuk;

  @override
  Widget build(BuildContext context) {
    final message = 'İade nedeniyle $debtBoncuk Boncuk sonraki kazanımlarından '
        'dengelenecek.';
    return Semantics(
      label: message,
      excludeSemantics: true,
      child: Container(
        key: const Key('abacusCardDebtExplainer'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: AppRadius.kMedium,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                message,
                style: AppTypography.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
