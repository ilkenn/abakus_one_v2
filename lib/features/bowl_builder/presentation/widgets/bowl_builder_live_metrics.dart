import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/bowl_builder_provider.dart';

/// The live price + nutrition dashboard — Fiyat/Kalori/Protein/Yağ/
/// Karbonhidrat/Malzeme, all sourced from `bowl_builder_provider.dart`'s
/// derived providers so this widget does no math of its own and only
/// rebuilds when one of those specific totals actually changes.
///
/// Deliberately shows absolute values only — no personal daily-goal
/// comparison (50g protein / 800 kcal targets etc.) since no product
/// decision on customer nutrition goals exists yet.
///
/// Orphaned as of B.3 (2026-08-18) — not instantiated anywhere. B.1
/// already removed its picking-step usage (the pinned
/// `BowlBuilderActionBar` readout replaced it there); B.3 then replaced
/// its Summary-step usage inside `BuilderSummary` with a purpose-built,
/// 5-field `_MacroSummaryCard` (no ingredient count — "Seçilen
/// Malzemeler" lists every selection individually instead). Left in
/// place, not deleted, per this project's no-silent-deletion rule.
class BowlBuilderLiveMetrics extends ConsumerWidget {
  const BowlBuilderLiveMetrics({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grandTotal = ref.watch(bowlBuilderGrandTotalProvider);
    final calories = ref.watch(bowlBuilderTotalCaloriesProvider);
    final protein = ref.watch(bowlBuilderTotalProteinProvider);
    final fat = ref.watch(bowlBuilderTotalFatProvider);
    final carbs = ref.watch(bowlBuilderTotalCarbsProvider);
    final count = ref.watch(bowlBuilderSelectedIngredientCountProvider);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kLarge,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: 'Fiyat',
              value: '${grandTotal.toStringAsFixed(0)} TL',
              emphasize: true,
            ),
          ),
          _divider(),
          Expanded(
            child: _Metric(
              label: 'Kalori',
              value: '${calories.toStringAsFixed(0)} kcal',
            ),
          ),
          _divider(),
          Expanded(
            child: _Metric(
              label: 'Protein',
              value: '${protein.toStringAsFixed(0)} g',
            ),
          ),
          _divider(),
          Expanded(
            child: _Metric(label: 'Yağ', value: '${fat.toStringAsFixed(0)} g'),
          ),
          _divider(),
          Expanded(
            child: _Metric(
              label: 'Karbonhidrat',
              value: '${carbs.toStringAsFixed(0)} g',
            ),
          ),
          _divider(),
          Expanded(
            child: _Metric(label: 'Malzeme', value: '$count'),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        color: AppColors.border,
      );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _Metric({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style:
              (emphasize ? AppTypography.titleMedium : AppTypography.labelLarge)
                  .copyWith(
            fontWeight: FontWeight.bold,
            color: emphasize ? AppColors.primary : AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
