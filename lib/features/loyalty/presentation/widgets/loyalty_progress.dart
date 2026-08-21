import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../domain/models/loyalty_account_snapshot.dart';

/// P3A Visual Polish (2026-08-24) — "Sonraki Boncuğa" earning progress
/// toward the next whole Boncuk, computed entirely from the server-
/// authoritative `earningRemainderMinorUnits`/`minorUnitsUntilNextBoncuk`
/// snapshot fields (BR-LOYALTY-001/BR-LOYALTY-015) — never derived from
/// local order history, never an independent client calculation of
/// eligible spend.
///
/// **Same-day correction (2026-08-24) — block-size-aware, not a fixed
/// rate.** The divisibility constraint on the server's earning ratio was
/// removed (e.g. `5000 minor units → 3 Boncuk` is now genuinely
/// supported), so there is no longer a single constant "per-Boncuk rate"
/// to use as the progress denominator. The denominator shown here is the
/// CURRENT block's actual size — `earningRemainderMinorUnits +
/// minorUnitsUntilNextBoncuk` — which is exact for the account's real
/// current position and, for a non-integer-reducible ratio, may differ
/// slightly from one block to the next (mathematically correct, not an
/// approximation).
class LoyaltyProgressCard extends StatelessWidget {
  const LoyaltyProgressCard({super.key, required this.snapshot});

  final LoyaltyAccountSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final remainderTl = snapshot.earningRemainderMinorUnits / 100;
    final neededTl = snapshot.minorUnitsUntilNextBoncuk / 100;
    final currentBlockMinorUnits = snapshot.earningRemainderMinorUnits +
        snapshot.minorUnitsUntilNextBoncuk;
    final currentBlockTl = currentBlockMinorUnits / 100;
    final progress = currentBlockMinorUnits == 0
        ? 0.0
        : snapshot.earningRemainderMinorUnits / currentBlockMinorUnits;
    final clampedProgress = progress.clamp(0, 1).toDouble();
    final progressPercent = (clampedProgress * 100).round();
    final semanticLabel = 'Sonraki Boncuğa ilerlemesi: '
        '${remainderTl.toStringAsFixed(0)} TL / ${currentBlockTl.toStringAsFixed(0)} TL, '
        'sonraki Boncuk için ${neededTl.toStringAsFixed(0)} TL kaldı';

    return AppCard(
      key: const Key('loyaltyProgressCard'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Semantics(
        label: semanticLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Sonraki Boncuğa', style: AppTypography.titleMedium),
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryExtraLight,
                      borderRadius: AppRadius.kPill,
                    ),
                    child: Text(
                      '%$progressPercent',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: AppRadius.kPill,
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    children: [
                      const ColoredBox(color: AppColors.surfaceVariant),
                      FractionallySizedBox(
                        widthFactor: clampedProgress,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primaryLight,
                                AppColors.primary,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ExcludeSemantics(
              child: Text(
                '${remainderTl.toStringAsFixed(0)} TL / ${currentBlockTl.toStringAsFixed(0)} TL',
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            ExcludeSemantics(
              child: Text(
                'Sonraki Boncuk için ${neededTl.toStringAsFixed(0)} TL kaldı',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
